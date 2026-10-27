# Differential test plan

The objective is to change one factor at a time and locate the first observable divergence between AC and battery. Do not start by forcing power limits: a benchmark score is not a thermal-safety signal, and current captures do not reveal the active throttle reason.

## Phase 0: establish repeatability

For each state, perform three runs under the same conditions. Alternate order (AC, battery, battery, AC) if convenient to limit warm-up/order bias. Keep the machine on a hard surface, use the same display/brightness/refresh rate, disconnect external displays, keep the battery charge range similar, and leave the same background applications open. Record ambient/fan/temperature context if available.

For every run record:

- date/time, power source verified by sysfs, battery percentage/status, selected profile;
- browser name, exact version, benchmark URL/version, fresh temporary profile, extensions disabled, browser energy saver state;
- Wayland or X11, GPU process/rendering status, display resolution and refresh rate;
- score and capture-log path;
- CPU package/core temperature, clocks, package watts, busy %, thermal-throttle count, and all available performance-limit flags.

Use the same benchmark page and wait until it is focused and idle. Avoid changing profile or launching unrelated work mid-run. Preserve the raw local capture, but publish only redacted summaries.

## Phase 1: validate the power-state CPU response

1. Resolve `rdmsr` access. Check `/dev/cpu/0/msr`, kernel `msr` module support/status, and permissions. If supported, load the module temporarily (`sudo modprobe msr`) and rerun the capture. Read registers only; do not write them.
2. Compare per-core HWP request values and `MSR_CORE_PERF_LIMIT_REASONS` around the benchmark on AC and battery. Decode flags against the Intel CPU model's documentation before interpreting them. Check whether flags are current or sticky status bits.
3. Capture `turbostat` while idle and during a short, repeatable CPU-only load on AC and battery. The short load distinguishes CPU scheduling/performance policy from browser/graphics effects. Stop if temperatures or fan behavior become abnormal.
4. Log Intel thermal sysfs zones, `dmesg` thermal/PROCHOT messages, `power_floor_status`, DPTF policy/device state, and power source transitions. Do not infer active DPTF limits from read-only min/max bounds alone.

Interpretation: if CPU-only workload clocks/package power also collapse on battery and a limit flag appears, prioritize firmware/EC/CPU policy. If CPU-only behavior is comparable but browser score collapses, investigate browser/graphics/session factors.

## Phase 2: separate desktop, display, and browser effects

Run only after the power-state CPU response is understood:

1. On the same Linux install and same battery state, compare GNOME Wayland vs GNOME Xorg (if available), then repeat on AC. Log session type rather than assuming it from browser flags.
2. Compare Brave and Firefox with fresh profiles, no extensions, same Speedometer version, and the same GPU. Confirm GPU renderer in each browser; record whether the Intel GPU is used for compositing and WebGL.
3. Compare a fixed display configuration: built-in panel only, fixed resolution/refresh rate/brightness. If necessary, test a lower refresh rate as a separate factor.
4. Temporarily disable browser battery/energy-saving features only as a controlled test; record setting and revert afterward.

Interpretation: a Wayland/X11 or browser-specific change should recur in multiple paired runs and should not be mistaken for a power-source effect. Similar CPU telemetry with different browser scores points toward rendering/browser stack.

## Phase 3: isolate Linux power-management ownership

Current capture found only `power-profiles-daemon` active among the four checked services. Confirm this at each test because NixOS configuration may change. Inventory other relevant units/processes and log them; do not run competing CPU tuners together. Compare profiles using identical runs, but do not assume the user-facing `performance` profile overrides firmware battery policy.

Check the Casper WMI `platform_profile` driver and kernel messages. Determine whether profile writes are accepted and whether a profile transition changes fan curve, CPU telemetry, or performance-limit flags on AC and battery. Avoid installing or enabling thermald, throttled, or a vendor-specific daemon until evidence points to a policy gap and compatibility with this HX system is established.

## Phase 4: Windows cross-check

Repeat clean-profile Speedometer tests on Windows battery and AC with the same display configuration and documented performance mode. Record exact browser builds and Windows power mode. During a short CPU-only load, capture effective clocks, package power, temperatures, and throttle indicators using a trusted monitor. Check whether DTT/IPF services are running during the test, not after it.

Windows is a useful comparison but not a perfect control: browser builds, drivers, firmware policy, and benchmark environment can differ. Compare repeated distributions and telemetry, not one score.

## Phase 5: change only a measured cause

After a specific limit is identified, test one reversible change at a time, starting with supported BIOS/OEM profile or Linux policy integration. Define a rollback before applying any change. Do not disable BDPROCHOT, raise PL1/PL2, alter voltage/current limits, or write arbitrary MSRs as a diagnostic experiment. Confirm sustained thermals and battery behavior before considering a persistent configuration change.

## Run ledger

Append rows to `results/run-ledger.csv`; use blank values rather than guessing. Keep detailed raw logs local in `captures/raw/` (ignored by Git). Share only sanitized output.

