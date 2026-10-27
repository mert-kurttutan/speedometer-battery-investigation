#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s ac|battery\n' "$0" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
expected_source=${1,,}
[[ "$expected_source" == ac || "$expected_source" == battery ]] || usage

detect_power_source() {
  local type_file online_file status_file
  shopt -s nullglob
  for type_file in /sys/class/power_supply/*/type; do
    [[ $(<"$type_file") == Mains ]] || continue
    online_file="${type_file%/type}/online"
    if [[ -r "$online_file" && $(<"$online_file") == 1 ]]; then
      printf 'ac\n'
      return
    fi
  done
  for status_file in /sys/class/power_supply/*/status; do
    if [[ -r "$status_file" && $(<"$status_file") == Discharging ]]; then
      printf 'battery\n'
      return
    fi
  done
  printf 'unknown\n'
}

power_source=$(detect_power_source)
if [[ "$power_source" != "$expected_source" ]]; then
  printf 'Expected %s, but sysfs reports %s. No capture started.\n' \
    "$expected_source" "$power_source" >&2
  exit 1
fi

if ! command -v turbostat >/dev/null 2>&1; then
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  repo_root=$(cd -- "$script_dir/.." && pwd)
  printf 'turbostat is not in PATH. On NixOS, try:\n' >&2
  printf '  nix develop %q -c %q %q\n' \
    "$repo_root" "$0" "$expected_source" >&2
  exit 127
fi

sudo -v

capture_dir=${CAPTURE_DIR:-/tmp/speedometer-power-captures}
mkdir -p "$capture_dir"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="$capture_dir/${timestamp}-${power_source}.log"

snapshot() {
  local f
  {
    printf '\n===== %s snapshot: ' "$1"
    date --iso-8601=seconds
    printf 'Reported power source: %s\n' "$(detect_power_source)"
    printf 'Expected capture: %s\n' "$expected_source"
    printf 'Kernel: '
    uname -r
    printf 'Power profile: '
    powerprofilesctl get 2>&1 || true
    printf 'Active power services:\n'
    systemctl is-active power-profiles-daemon tlp auto-cpufreq thermald 2>&1 || true

    printf '\n--- Battery status ---\n'
    for f in /sys/class/power_supply/*/{status,capacity,voltage_now,current_now,power_now}; do
      if [[ -r "$f" ]]; then printf '%s: %s\n' "$f" "$(<"$f")"; fi
    done

    printf '\n--- Intel P-state and CPU frequency policies ---\n'
    for f in /sys/devices/system/cpu/intel_pstate/{status,no_turbo,min_perf_pct,max_perf_pct}; do
      if [[ -r "$f" ]]; then printf '%s: %s\n' "$f" "$(<"$f")"; fi
    done
    for f in /sys/devices/system/cpu/cpufreq/policy*/{scaling_driver,scaling_governor,scaling_min_freq,scaling_max_freq,scaling_cur_freq,energy_performance_preference}; do
      if [[ -r "$f" ]]; then printf '%s: %s\n' "$f" "$(<"$f")"; fi
    done

    printf '\n--- ACPI platform profile ---\n'
    for f in /sys/firmware/acpi/platform_profile /sys/firmware/acpi/platform_profile_choices; do
      if [[ -r "$f" ]]; then printf '%s: %s\n' "$f" "$(<"$f")"; fi
    done

    printf '\n--- Intel RAPL limits and energy counters ---\n'
    for f in /sys/class/powercap/intel-rapl*/{name,energy_uj,max_energy_range_uj,constraint_*_name,constraint_*_power_limit_uw,constraint_*_time_window_us}; do
      if [[ -r "$f" ]]; then printf '%s: %s\n' "$f" "$(<"$f")"; fi
    done

    printf '\n--- Intel DPTF processor power-limit interfaces ---\n'
    for f in /sys/bus/pci/devices/*/power_limits/*; do
      if [[ -r "$f" && -f "$f" ]]; then printf '%s: %s\n' "$f" "$(<"$f")"; fi
    done

    printf '\n--- Read-only CPU MSR limits (rdmsr output is CPU order) ---\n'
    if command -v rdmsr >/dev/null 2>&1; then
      printf 'IA32_HWP_REQUEST 0x774 (all CPUs):\n'
      sudo rdmsr -a 0x774 2>&1 || true
      printf 'MSR_CORE_PERF_LIMIT_REASONS 0x64f (all CPUs):\n'
      sudo rdmsr -a 0x64f 2>&1 || true
      printf 'MSR_PKG_POWER_LIMIT 0x610 (CPU 0):\n'
      sudo rdmsr -p 0 0x610 2>&1 || true
    else
      printf 'rdmsr unavailable; run via the provided nix develop shell.\n'
    fi
  } >>"$log_file"
}

snapshot before
printf 'Writing capture to %s\n' "$log_file"
printf 'Run Speedometer now. Press Ctrl-C after the run finishes to stop and save the capture.\n'
printf '\n===== turbostat (1-second intervals) =====\n' >>"$log_file"

finish_capture() {
  trap - INT TERM
  snapshot after
  printf '\nSpeedometer score (press Enter to leave blank): '
  IFS= read -r score || score=''
  printf 'Recorded Speedometer score: %s\n' "${score:-not provided}" >>"$log_file"
  printf 'Capture saved: %s\n' "$log_file"
  exit 0
}

trap finish_capture INT TERM
sudo turbostat --interval 1 2>&1 | tee -a "$log_file"
