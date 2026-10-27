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

New Windows captures on 2026-10-27 used the Balanced power plan and scored 14.5 on battery and 41.9 on AC. The 100-second battery capture contained about 30 seconds of benchmark activity; the 25-second AC capture contained about 12 seconds, with activity falling toward idle afterward. The operator confirmed that the AC capture covered the full test. Both captures verified their power source, showed a 2560x1600 display at 165 Hz, and found `dptftcs` and `ipfsvc` running. The selected Windows power mode and exact browser build were not recorded. The average Windows CPU performance counter during active samples was about 71 on battery versus 207 on AC; this counter is not a direct CPU clock reading and does not identify a throttle cause. The `PerformanceLimitFlags` value was 2 in both captures and has not been decoded. The Balanced plan had a 100% maximum processor state for both AC and battery; its cooling policy was Active on AC and Passive on battery.

Brave's GPU diagnostics showed hardware-accelerated Intel/Mesa rendering on Wayland. That makes software GPU rendering a weak explanation, but the diagnostic does not rule out compositor, graphics-driver, or browser differences. Firefox showing the same battery symptom makes a Brave-only issue unlikely.

## Latest captures

Earlier NixOS raw captures are tracked in `captures/raw/` in this public repository and remain on the original machine under `/tmp/speedometer-power-captures/` as well. New Windows raw captures remain local pending review for public release; their summarized measurements are below.

- AC run: `20261027T171317Z-ac.log`, score 42.8; the earlier AC run scored 40.0.
- Battery run: `20261027T123634Z-battery.log`, score 4.44.
- Windows battery run: `20261027T133035Z-windows-battery.log`, score 14.5.
- Windows AC run: `20261027T133402Z-windows-ac.log`, score 41.9.
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

## CPU-only pinned-load comparison

Paired 30-second `stress-ng` matrix-product loads were pinned to logical CPU 0 with the performance profile selected. Power source was verified by sysfs before and after each run:

| Power | Busy frequency | CPU busy | Package power | Core / package temperature | `stress-ng` ops/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Battery | 588 MHz | 99.76% | 6.54 W | 34°C / 44°C | 390 |
| AC | 4,997 MHz | 99.76% | 54.37 W | 93°C / 93°C | 3,412 |

Both runs reported the performance profile, platform profile `performance`, governor `powersave`, turbo enabled, `max_perf_pct=100`, CPU 0 HWP request `0x430b`, MSR `0x64f` value `0x19030100`, and package power limit MSR `0x610` value `0x42841000df8370`. The CPU-only throughput and busy frequency were roughly 8.5 times higher on AC. The battery CPU stayed cool and had no `CoreThr` count; AC reached 93°C and turbostat reported `CoreThr=4345`, so AC thermal behavior should be considered when interpreting its maximum performance. These captures establish that the battery slowdown is below the browser/rendering layer, but do not identify the control enforcing it.

Raw logs: `20261027T175644Z-cpu-load-battery-cpu0.log` and `20261027T174522Z-cpu-load-ac-cpu0.log`.

## Windows CPU-only pinned-load comparison

Paired 30-second .NET CPU-loop runs pinned to logical CPU 0 were captured under the Balanced power plan. WMI verified battery and AC respectively before each run, and `dptftcs` and `ipfsvc` were running in both. Each log contains 23 samples.

| Power | Mean CPU 0 performance counter | Mean CPU 0 utility counter | Mean total CPU utility counter |
| --- | ---: | ---: | ---: |
| Battery | 158.9 | 158.8 | 5.3 |
| AC | 238.1 | 238.2 | 9.0 |

The CPU 0 performance counter was about 1.50 times higher on AC. Windows processor utility can exceed 100 because it scales work by processor performance state; these are not percentages of elapsed time busy. The logged `ProcessorFrequency` field alternated between 1466 and 2200 MHz on both power sources and was lower on average on AC, contrary to the performance counter. It should not be interpreted here as an effective clock reading. The script did not capture package watts, temperature, time-based CPU busy, or a comparable throughput rate. The selected Windows power mode was not recorded separately from the active Balanced plan. These Windows counters support a smaller battery-versus-AC performance change than the Linux `stress-ng` result, but the workloads and measurement methods differ, so their ratios are not directly comparable. The cause of the NixOS battery limit remains unknown.

Raw logs: `20261027T152707Z-cpu-load-windows-battery.log` and `20261027T152853Z-cpu-load-windows-ac.log`. Earlier script attempts exited before sampling because the .NET worker used an invalid `volatile double` declaration; the local script now uses `volatile float` and completed both runs.

Paired HWiNFO sensor logs were then recorded during another 30-second Windows CPU 0 load on each power source. The steady intervals below omit the first sensor sample after the CPU-load script began. Each interval has 14 samples, and HWiNFO reports P-core 0 thread 0 at 100% usage in every sample.

| Windows source | P-core 0 thread 0 effective clock | CPU package power | Package temperature | Core 0 / package thermal and power-limit flags |
| --- | ---: | ---: | ---: | --- |
| Battery | 3,274 MHz | 11.2 W | 47.6 C | No |
| AC | 5,139 MHz | 27.4 W | 57.6 C | No |

Windows battery retained about 64% of its AC effective clock in this pinned load; the NixOS `stress-ng` battery run retained about 12% of its AC busy frequency. Both operating systems show a battery-state reduction, but the NixOS frequency collapse is much more severe. The Windows and NixOS load programs and telemetry differ, so package-power and throughput ratios should not be directly equated. These measurements do not identify whether the cross-OS gap comes from Windows power mode, OS policy integration, firmware/EC behavior, or another battery-state control. The selected Windows power mode remains unrecorded separately from the Balanced plan.

The HWiNFO CSV files remain local at `C:\Program Files\HWiNFO64\ac-log.csv` and `battery-log.csv`. The matching CPU-load captures are `20261027T154123Z-cpu-load-windows-ac.log` and `20261027T154450Z-cpu-load-windows-battery.log` in `captures/raw/`.

## Leading causes to distinguish

1. Firmware/EC or platform battery-state power policy, including limits not represented in the sampled RAPL sysfs constraints.
2. Electrical/current or other hardware constraints; the generic `Other` flag is active on AC and battery and needs more specific telemetry.
3. Battery-specific GPU/compositor/display policy, despite hardware rendering being enabled.
4. Benchmark/browser environmental differences: background load, profile/extension state, browser build, refresh rate, or power-saving feature.
5. ACPI/DPTF policy integration or Casper platform-profile implementation differences.

