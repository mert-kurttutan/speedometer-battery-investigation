#!/usr/bin/env nu

def detect-power-source [] {
  for f in (glob --follow-symlinks '/sys/class/power_supply/*/type') {
    let kind = (open $f | str trim)
    if $kind == "Mains" {
      let online = ($f | path dirname | path join online)
      if (try { (open $online | str trim) == "1" } catch { false }) {
        return "ac"
      }
    }
  }
  for f in (glob --follow-symlinks '/sys/class/power_supply/*/status') {
    if (try { (open $f | str trim) == "Discharging" } catch { false }) {
      return "battery"
    }
  }
  "unknown"
}

def read-sysfs [pattern: string] {
  glob --follow-symlinks $pattern
  | each {|f| try { $"($f): ((open $f | str trim))" } catch { "" } }
  | where {|line| $line != "" }
  | str join "\n"
}

def append-text [file: string, value: string] {
  $value | save --append $file
}

def capture-snapshot [file: string, label: string] {
  let profile = (^powerprofilesctl get | complete)
  let services = (^systemctl is-active power-profiles-daemon tlp auto-cpufreq thermald | complete)
  let msr = if (which rdmsr | is-not-empty) {
    let hwp = (^sudo rdmsr -a 0x774 | complete)
    let reasons = (^sudo rdmsr -a 0x64f | complete)
    let pkg = (^sudo rdmsr -p 0 0x610 | complete)
    $"IA32_HWP_REQUEST 0x774:\n(($hwp.stdout | str trim))\n(($hwp.stderr | str trim))\nMSR_CORE_PERF_LIMIT_REASONS 0x64f:\n(($reasons.stdout | str trim))\n(($reasons.stderr | str trim))\nMSR_PKG_POWER_LIMIT 0x610:\n(($pkg.stdout | str trim))\n(($pkg.stderr | str trim))"
  } else {
    "rdmsr unavailable"
  }
  let block = $"\n===== ($label) snapshot: ((date now | format date '%Y-%m-%dT%H:%M:%S%:z')) =====
Reported power source: (detect-power-source)
Kernel: (sys host | get kernel_version)
Power profile: (($profile.stdout | str trim))
Power services (power-profiles-daemon, tlp, auto-cpufreq, thermald):
(([$services.stdout, $services.stderr] | str join "\n" | str trim))

--- Battery ---
(read-sysfs '/sys/class/power_supply/*/{status,capacity,voltage_now,current_now,power_now}')

--- Intel P-state / cpufreq ---
(read-sysfs '/sys/devices/system/cpu/intel_pstate/{status,no_turbo,min_perf_pct,max_perf_pct}')
(read-sysfs '/sys/devices/system/cpu/cpufreq/policy*/{scaling_driver,scaling_governor,scaling_min_freq,scaling_max_freq,energy_performance_preference}')

--- ACPI platform profile ---
(read-sysfs '/sys/firmware/acpi/platform_profile{,_choices}')

--- RAPL power limits and energy ---
(read-sysfs '/sys/class/powercap/intel-rapl*/{name,energy_uj,max_energy_range_uj,constraint_*_name,constraint_*_power_limit_uw,constraint_*_time_window_us}')

--- DPTF processor power-limit interface ---
(read-sysfs '/sys/bus/pci/devices/*/power_limits/*')

--- Read-only MSRs ---
($msr)
"
  append-text $file $block
}

def main [expected_source: string, duration: int = 240] {
  if ($expected_source not-in ["ac", "battery"]) {
    error make {msg: "Usage: nu scripts/capture-linux.nu ac|battery [duration-seconds]"}
  }
  let source = (detect-power-source)
  if $source != $expected_source {
    error make {msg: $"Expected ($expected_source), sysfs reports ($source); capture stopped."}
  }
  if (which turbostat | is-empty) {
    error make {msg: "turbostat missing. Run this script inside `nix develop`."}
  }
  ^sudo -v
  let capture_dir = ($env.CAPTURE_DIR? | default '/tmp/speedometer-power-captures')
  mkdir $capture_dir
  let stamp = (date now | format date '%Y%m%dT%H%M%SZ')
  let log = ($capture_dir | path join $"($stamp)-($source).log")
  capture-snapshot $log "before"
  print $"Writing to ($log). Start Speedometer now; telemetry runs for ($duration) seconds."
  append-text $log "\n===== turbostat (1-second intervals) =====\n"
  let sample = (^sudo timeout $"($duration)s" turbostat --interval 1 | complete)
  append-text $log $sample.stdout
  if ($sample.stderr | str trim) != "" { append-text $log $sample.stderr }
  capture-snapshot $log "after"
  let score = (input "Speedometer score (Enter to leave blank): ")
  append-text $log $"\nRecorded Speedometer score: (($score | str trim | default 'not provided'))\n"
  print $"Capture saved: ($log)"
}
