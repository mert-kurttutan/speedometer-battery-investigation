#!/usr/bin/env nu

def detect-power-source [] {
  for f in (glob --follow-symlinks '/sys/class/power_supply/*/type') {
    if ((open $f | str trim) == 'Mains') {
      let online = ($f | path dirname | path join 'online')
      if (try { (open $online | str trim) == '1' } catch { false }) { return 'ac' }
    }
  }
  for f in (glob --follow-symlinks '/sys/class/power_supply/*/status') {
    if (try { (open $f | str trim) == 'Discharging' } catch { false }) { return 'battery' }
  }
  'unknown'
}

def read-value [path: string] {
  try { open $path | str trim } catch { 'unavailable' }
}

def battery-value [field: string] {
  let paths = (glob --follow-symlinks $"/sys/class/power_supply/*/($field)")
  let batteries = ($paths | where {|path| (try { open ($path | path dirname | path join 'type') | str trim } catch { '' }) == 'Battery' })
  if ($batteries | is-empty) { 'unavailable' } else { read-value ($batteries | first) }
}

def append-text [file: string, value: string] {
  $value | save --append $file
}

def snapshot [file: string, label: string, cpu: int, rdmsr: string] {
  let hwp = (^sudo $rdmsr -p $cpu 0x774 | complete)
  let limit = (^sudo $rdmsr -p $cpu 0x64f | complete)
  let pkg = (^sudo $rdmsr -p 0 0x610 | complete)
  let profile = (^powerprofilesctl get | complete)
  let block = $"\n===== ($label) snapshot: ((date now | format date '%Y-%m-%dT%H:%M:%S%:z')) =====
Power source: (detect-power-source)
Profile: (($profile.stdout | str trim))
Platform profile: (read-value '/sys/firmware/acpi/platform_profile')
Battery status: (battery-value 'status')
Battery capacity: (battery-value 'capacity')
no_turbo: (read-value '/sys/devices/system/cpu/intel_pstate/no_turbo')
max_perf_pct: (read-value '/sys/devices/system/cpu/intel_pstate/max_perf_pct')
CPU ($cpu) HWP request 0x774: (($hwp.stdout | str trim)) (($hwp.stderr | str trim))
CPU ($cpu) performance limit reasons 0x64f: (($limit.stdout | str trim)) (($limit.stderr | str trim))
Package power limit 0x610: (($pkg.stdout | str trim)) (($pkg.stderr | str trim))
"
  append-text $file $block
}

def main [expected_source: string, cpu: int = 0, duration: int = 30] {
  if ($expected_source not-in ['ac', 'battery']) {
    error make {msg: 'Usage: nu scripts/capture-cpu-load.nu ac|battery [cpu-id] [duration-seconds]'}
  }
  if (detect-power-source) != $expected_source {
    error make {msg: $"Expected ($expected_source), sysfs reports (detect-power-source); test stopped."}
  }
  let cpu_count = (glob --follow-symlinks '/sys/devices/system/cpu/cpu[0-9]*' | length)
  if $cpu < 0 or $cpu >= $cpu_count {
    error make {msg: $"CPU id ($cpu) is outside the available range 0..($cpu_count - 1)."}
  }
  for tool in ['turbostat', 'stress-ng', 'taskset', 'rdmsr'] {
    if (which $tool | is-empty) {
      error make {msg: $"($tool) missing. Run this script inside `nix develop`."}
    }
  }
  let turbo = (which turbostat | first | get path)
  let stress = (which stress-ng | first | get path)
  let taskset = (which taskset | first | get path)
  let rdmsr = (which rdmsr | first | get path)
  ^sudo -v
  let dir = ($env.CAPTURE_DIR? | default '/tmp/speedometer-power-captures')
  mkdir $dir
  let stamp = (date now | format date '%Y%m%dT%H%M%SZ')
  let log = ($dir | path join $"($stamp)-cpu-load-($expected_source)-cpu($cpu).log")
  $"Test: single logical CPU load\nPower source: ($expected_source)\nCPU: ($cpu)\nDuration: ($duration) seconds\n" | save $log
  snapshot $log 'before' $cpu $rdmsr
  print $"Writing to ($log). Starting a ($duration)-second CPU-only load on CPU ($cpu)."
  append-text $log "\n===== turbostat and stress-ng =====\n"
  let run = (^sudo $turbo --interval 1 --cpu $cpu -- $taskset -c $cpu $stress --cpu 1 --cpu-method matrixprod --timeout $"($duration)s" --metrics-brief | complete)
  append-text $log $run.stdout
  if ($run.stderr | str trim) != '' { append-text $log $run.stderr }
  snapshot $log 'after' $cpu $rdmsr
  print $"Capture saved: ($log)"
}
