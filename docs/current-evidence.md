# Current evidence

## Machine and comparison

- Laptop: Casper Excalibur G911
- CPU: Intel Core i9-13900HX (24 cores / 32 logical processors)
- GPUs: Intel UHD integrated graphics and NVIDIA GeForce RTX 4070 Laptop GPU
- Windows firmware services observed running: Intel Dynamic Tuning Telemetry Service (`dptftcs`) and Intel Innovation Platform Framework (`ipfsvc`). The active Windows power plan was inspected after prior benchmark runs, so it does not establish the plan used during those runs.

## Scores recorded so far

| OS | Power source | Power saver | Balanced | Performance |
| --- | --- | ---: | ---: | ---: |
| NixOS | Battery | 4.37–4.39 | 4.43 | 4.44–4.45 |
| NixOS | AC | 17.6 | 34.6 | 43.2 |
| Windows | Battery |  | 15.2–15.9 |  |
| Windows | AC |  |  | 42–43 |

Additional runs: Brave Wayland on NixOS battery about 4.4; Brave X11 about 4.11; Firefox about 3.9. A later NixOS performance-profile capture gave AC 40.0 and battery 4.44.

Brave's GPU diagnostics showed hardware-accelerated Intel/Mesa rendering on Wayland. That makes software GPU rendering a weak explanation, but the diagnostic does not rule out compositor, graphics-driver, or browser differences. Firefox showing the same battery symptom makes a Brave-only issue unlikely.

## Latest captures

Raw captures are tracked in `captures/raw/` in this public repository and remain on the original machine under `/tmp/speedometer-power-captures/` as well.

- AC run: `20261027T171317Z-ac.log`, score 42.8; the earlier AC run scored 40.0.
- Battery run: `20261027T123634Z-battery.log`, score 4.44.
- Both: performance profile; `power-profiles-daemon` active; TLP, auto-cpufreq, and thermald inactive; Intel P-state active; turbo enabled (`no_turbo=0`); `max_perf_pct=100`; RAPL package PL1=110 W, PL2=130 W, constraint 2=246 W; MMIO PL1=110 W.
- Both captures reported the same ACPI platform profile (`performance`) and exposed DPTF processor power-limit bounds.
- The attempted MSR reads were empty and followed by `rdmsr: open: No such file or directory`. No MSR throttle reason can be inferred from these captures.

## HWP and limit-reason captures on both power sources

Three Nushell captures include successful MSR reads while Speedometer ran:

- `20261027T170343Z-battery.log`: score 4.37, power-saver profile, ACPI platform profile `low-power`.
- `20261027T170722Z-battery.log`: score 4.44, performance profile, ACPI platform profile `performance`.
- `20261027T171317Z-ac.log`: score 42.8, performance profile, ACPI platform profile `performance`.

Both still show turbo enabled, `max_perf_pct=100`, and the same exposed RAPL limits (PL1 110 W, PL2 130 W, constraint 2 246 W). The HWP EPP changed as requested: the power-saver capture has EPP `0xff`; the performance capture has EPP `0x00`. Their Speedometer scores barely changed. The maximum-performance request values remain `0x43`, `0x45`, and `0x27` across the P-core/E-core groups; CPU 0's HWP highest-performance capability is `0x43`.

`MSR_CORE_PERF_LIMIT_REASONS` was `0x19030100` on all logical CPUs before and after **all three** runs, including AC. Its current-status bit 8 (`Other`) is defined by Intel as frequency clipping due to electrical or other constraints. Since it is also set during the fast AC run, it does not distinguish the battery slowdown or identify its cause. The upper log bits contain historical events and must not be confused with current status. An earlier one-off AC read had bit 8 clear, showing that this status can vary with sampling time/workload.

During the 200-second power-saver battery capture, turbostat recorded 196 package intervals: mean package busy 6.71%, busy frequency 538 MHz, and package power 7.14 W. On intervals with more than 1% package busy, those means were 523 MHz and 7.48 W. The performance-profile battery run recorded 117 intervals, with busy frequency 500 MHz and package power 7.87 W; `CoreThr` stayed zero.

The 40-second AC run recorded 39 package intervals: on intervals with more than 1% package busy, mean busy frequency was 4,202 MHz and package power 57.42 W. AC and battery performance-profile runs had the same HWP EPP (`0x00`), maximum-performance requests, exposed PL1/PL2 limits, and `0x19030100` limit-reason value, yet their scores were 42.8 and 4.44. The active frequency/power divergence is clear; the generic bit 8 flag is not the battery-specific explanation. An unexposed battery-state platform or electrical power restriction remains a leading hypothesis, but its exact control source is unknown.

## Leading causes to distinguish

1. Firmware/EC or platform battery-state power policy, including limits not represented in the sampled RAPL sysfs constraints.
2. Electrical/current or other hardware constraints; the generic `Other` flag is active on AC and battery and needs more specific telemetry.
3. Battery-specific GPU/compositor/display policy, despite hardware rendering being enabled.
4. Benchmark/browser environmental differences: background load, profile/extension state, browser build, refresh rate, or power-saving feature.
5. ACPI/DPTF policy integration or Casper platform-profile implementation differences.

