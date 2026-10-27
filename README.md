# NixOS battery Speedometer investigation

Determine why Speedometer 3.1 runs much slower on battery in NixOS than on battery in Windows on the same Casper Excalibur G911, and identify a safe, evidence-based fix if one exists.

## Current result

The large difference reproduces in Chromium-based Brave and Firefox on Linux, and across Brave Wayland and X11 runs. NixOS reaches approximately the Windows AC result while plugged in. A pinned CPU-only load now also shows a severe battery-specific CPU performance drop on NixOS, so Wayland and browser rendering cannot explain the main slowdown. The enforcement mechanism remains unknown.

The newest controlled capture pair:

| Source | Speedometer 3.1 | Profile | `no_turbo` | `max_perf_pct` | RAPL PL1/PL2 |
| --- | ---: | --- | ---: | ---: | ---: |
| NixOS AC | 42.8 | performance | 0 | 100 | 110 W / 130 W |
| NixOS battery | 4.44 | performance | 0 | 100 | 110 W / 130 W |

On a 30-second single-core CPU load pinned to CPU 0, NixOS battery reached 588 MHz / 6.54 W package power / 390 stress-ng ops/s; AC reached 4,997 MHz / 54.37 W / 3,412 ops/s. Both runs had 99.76% CPU busy, performance profiles, turbo enabled, the same HWP request, and the same exposed RAPL limit. The battery run stayed cool at 34°C core / 44°C package. See the raw captures and analysis in [current evidence](docs/current-evidence.md).

MSR readings are now available after loading the `msr` kernel module. The equal HWP and RAPL requests do not explain the large difference in effective clock and package power; the active battery-state limit remains unidentified.

Earlier measurements include NixOS battery scores around 4.4, Windows battery around 15–16, and AC scores around 40–43 on both systems. See [current evidence](docs/current-evidence.md) and [test plan](docs/test-plan.md).

## Run the capture

The capture scripts use Nushell on both operating systems. On NixOS, enter the pinned development environment and run:

```sh
nix develop -c nu scripts/capture-linux.nu ac
nix develop -c nu scripts/capture-linux.nu battery
```

The Linux script samples for 240 seconds by default. Start Speedometer as soon as it says to. Set a different duration as the third argument. Logs default to `/tmp/speedometer-power-captures/`; copy captures you want to preserve into `captures/raw/` before committing.

### Windows setup and capture

1. Open PowerShell. If Git is not installed, install Git for Windows:

   ```powershell
   winget install --id Git.Git --exact
   ```

2. Install Nushell using its official Windows package:

   ```powershell
   winget install --id Nushell.Nushell --exact
   ```

   Close and reopen the terminal after installation, then run `nu` to start Nushell.

3. In Nushell, clone this repository and enter it:

   ```nu
   git clone https://github.com/mert-kurttutan/speedometer-battery-investigation.git
   cd speedometer-battery-investigation
   ```

4. Close unnecessary applications and use the same browser build, Speedometer 3.1 page, browser profile, display resolution, refresh rate, and brightness for both runs. Keep the benchmark tab focused. Do not change the Windows power mode between the AC and battery captures; the script records the active plan and its AC/DC CPU policy.

5. Unplug the charger and run the battery capture:

   ```nu
   nu scripts/capture-windows.nu battery 300
   ```

   Start Speedometer as soon as the script says it is recording. It samples for 300 seconds, then asks for the score.

6. Connect the charger, confirm Windows is on AC, and repeat:

   ```nu
   nu scripts/capture-windows.nu ac 300
   ```

The script verifies the power source through WMI and records the active power plan, AC/DC processor policy, battery state, Intel DTT/IPF service state, CPU frequency/performance-limit counters, and available 3D GPU engine counters. It does not change power settings. Logs are written to `%TEMP%\speedometer-power-captures\`.

For a CPU-only comparison, run the separate pinned-load capture on battery, then AC, with the same Windows power mode:

```nu
nu scripts/capture-cpu-load-windows.nu battery 30
nu scripts/capture-cpu-load-windows.nu ac 30
```

This runs a single-thread CPU load pinned to logical CPU 0 and records per-core and total CPU performance counters, the active power plan, and Intel DTT/IPF service state. It verifies the power source and writes logs to `%TEMP%\speedometer-power-captures\`. The worker uses a small .NET CPU loop, so compare frequency and utilization across power sources; its work rate is not directly comparable to Linux `stress-ng`.

To add the two Windows logs to this repository, copy the generated files into `captures/raw/`, then review and commit them:

```nu
cp $'($env.TEMP)\speedometer-power-captures\<battery-log-name>.log' captures/raw/
cp $'($env.TEMP)\speedometer-power-captures\<ac-log-name>.log' captures/raw/
git add captures/raw
git commit -m 'Add Windows AC and battery captures'
git push
```

Replace the placeholder names with the actual timestamped filenames. Git authentication is required to push; Git for Windows includes Git Credential Manager, so the GitHub CLI is not needed.

To troubleshoot missing MSR devices on NixOS, check `ls -l /dev/cpu/0/msr` and `lsmod | rg '^msr'`; if the kernel supports the module, a temporary `sudo modprobe msr` may create the device. Do not enable persistent module settings or write any MSR as part of diagnosis.

## Cross-machine use

This directory is pushed to a public GitHub repository. Clone it on another computer with `git`; Codex CLI can then be started from the cloned directory without `gh`.

