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

- AC run: `20261027T123545Z-ac.log`, score 40.0.
- Battery run: `20261027T123634Z-battery.log`, score 4.44.
- Both: performance profile; `power-profiles-daemon` active; TLP, auto-cpufreq, and thermald inactive; Intel P-state active; turbo enabled (`no_turbo=0`); `max_perf_pct=100`; RAPL package PL1=110 W, PL2=130 W, constraint 2=246 W; MMIO PL1=110 W.
- Both captures reported the same ACPI platform profile (`performance`) and exposed DPTF processor power-limit bounds.
- The attempted MSR reads were empty and followed by `rdmsr: open: No such file or directory`. No MSR throttle reason can be inferred from these captures.

## New battery MSR captures

Two Nushell captures now include successful MSR reads while Speedometer ran:

- `20261027T170343Z-battery.log`: score 4.37, power-saver profile, ACPI platform profile `low-power`.
- `20261027T170722Z-battery.log`: score 4.44, performance profile, ACPI platform profile `performance`.

Both still show turbo enabled, `max_perf_pct=100`, and the same exposed RAPL limits (PL1 110 W, PL2 130 W, constraint 2 246 W). The HWP EPP changed as requested: the power-saver capture has EPP `0xff`; the performance capture has EPP `0x00`. Their Speedometer scores barely changed. The maximum-performance request values remain `0x43`, `0x45`, and `0x27` across the P-core/E-core groups; CPU 0's HWP highest-performance capability is `0x43`.

Most significant: `MSR_CORE_PERF_LIMIT_REASONS` was `0x19030100` on all logical CPUs in both battery captures, before and after sampling. Its current-status bit 8 (`Other`) was set; Intel defines this as frequency clipping due to electrical or other constraints. The upper log bits also contain historical events and must not be confused with the current bit. A prior AC CPU 0 read was `0x19030000` (bit 8 clear), so AC capture telemetry should establish whether this status reliably separates battery from AC during the benchmark.

During the 200-second battery capture, turbostat recorded 196 package intervals: mean package busy 6.71%, mean busy frequency 538 MHz, and mean package power 7.14 W. On intervals with more than 1% package busy, mean busy frequency was 523 MHz and package power 7.48 W. The 120-second performance-profile capture recorded 117 intervals with mean busy frequency 500 MHz and package power 7.87 W; `CoreThr` remained zero. This aligns with the active electrical/other limit and makes a profile-only or core-thermal explanation unlikely, though it does not identify the exact firmware/EC/VR mechanism.

Earlier turbostat capture showed an on-battery collapse in active CPU frequency and package power during Speedometer, with no core thermal-throttle counter events in the battery intervals. This suggests an effective battery-state CPU limit that is not explained by the sampled sysfs knobs. It does not identify the limiting mechanism. Preserve that as the current leading hypothesis, not a proven DTT/BDPROCHOT diagnosis.

## Leading causes to distinguish

1. Firmware/EC or Intel DTT/IPF battery policy, including a hardware limit not represented in the sampled RAPL sysfs constraints.
2. CPU performance limit reason (thermal, electrical/current, PROCHOT/BDPROCHOT, package power, HWP request, or platform policy).
3. Battery-specific GPU/compositor/display policy, despite hardware rendering being enabled.
4. Benchmark/browser environmental differences: background load, profile/extension state, browser build, refresh rate, or power-saving feature.
5. ACPI/DPTF policy integration or Casper platform-profile implementation differences.

