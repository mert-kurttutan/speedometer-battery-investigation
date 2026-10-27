# NixOS battery Speedometer investigation

Determine why Speedometer 3.1 runs much slower on battery in NixOS than on battery in Windows on the same Casper Excalibur G911, and identify a safe, evidence-based fix if one exists.

## Current result

The large difference reproduces in Chromium-based Brave and Firefox on Linux, and across Brave Wayland and X11 runs. NixOS reaches approximately the Windows AC result while plugged in. This makes a Linux battery-state performance limit the leading hypothesis; the evidence does not yet identify whether it comes from firmware/EC policy, a kernel interface, CPU throttling reason, or another component.

The newest controlled capture pair:

| Source | Speedometer 3.1 | Profile | `no_turbo` | `max_perf_pct` | RAPL PL1/PL2 |
| --- | ---: | --- | ---: | ---: | ---: |
| NixOS AC | 40.0 | performance | 0 | 100 | 110 W / 130 W |
| NixOS battery | 4.44 | performance | 0 | 100 | 110 W / 130 W |

Capture scripts attempted to read MSRs `0x774`, `0x64f`, and `0x610`, but `rdmsr` returned `No such file or directory`; those readings are **not available yet**. The exposed settings above being equal does not prove that the effective hardware limits are equal.

Earlier measurements include NixOS battery scores around 4.4, Windows battery around 15–16, and AC scores around 40–43 on both systems. See [current evidence](docs/current-evidence.md) and [test plan](docs/test-plan.md).

## Run the capture

From this repository on NixOS, with AC or battery as indicated:

```sh
nix develop -c ./scripts/capture-speedometer-power.sh ac
nix develop -c ./scripts/capture-speedometer-power.sh battery
```

Run the script immediately before starting Speedometer. Press Ctrl-C after the benchmark finishes, then enter the displayed score. Logs default to `/tmp/speedometer-power-captures/` and are intentionally excluded from Git.

The current script requires `turbostat` and `sudo`. The flake also provides `rdmsr`. To troubleshoot the missing MSR device, check `ls -l /dev/cpu/0/msr` and `lsmod | rg '^msr'`; if the kernel supports the module, a temporary `sudo modprobe msr` may create the device. Do not enable any persistent module setting or write any MSR as part of diagnosis.

## Cross-machine use

Once this directory is pushed to a private GitHub repository, clone it on another computer with `git` and authenticate that computer to GitHub. Codex CLI can then be started from the cloned directory; it does not require `gh` if Git authentication is already configured.

