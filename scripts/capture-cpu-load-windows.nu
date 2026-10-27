#!/usr/bin/env nu

def run-powershell [script: string] {
  ^powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $script | complete
}

def main [expected_source: string, duration: int = 30] {
  if ($expected_source not-in ["ac", "battery"]) {
    error make {msg: "Usage: nu scripts/capture-cpu-load-windows.nu ac|battery [duration-seconds]"}
  }
  if not ((sys host | get name | str lowercase | str contains "windows")) {
    error make {msg: "Run this script in Nushell on Windows."}
  }

  let ps = '
$ErrorActionPreference = "Stop"
$expected = "EXPECTED_SOURCE"
$duration = DURATION_SECONDS
$root = Join-Path $env:TEMP "speedometer-power-captures"
New-Item -ItemType Directory -Force -Path $root | Out-Null
$stamp = Get-Date -Format "yyyyMMddTHHmmssK"
$log = Join-Path $root "$stamp-cpu-load-windows-$expected.log"

function Get-PowerSource {
  $status = Get-CimInstance -Namespace root/WMI -ClassName BatteryStatus -ErrorAction SilentlyContinue
  if ($status.PowerOnline -contains $true) { return "ac" }
  if ($status.Discharging -contains $true) { return "battery" }
  return "unknown"
}

$source = Get-PowerSource
if ($source -ne $expected) { throw "Expected $expected, Windows battery telemetry reports $source; test stopped." }

$workerPath = Join-Path $root "cpu-load-worker-$([guid]::NewGuid().ToString()).ps1"
$workerScript = @"
`$p = Get-Process -Id `$PID
`$p.ProcessorAffinity = [IntPtr]1
Add-Type -TypeDefinition "using System; public static class CpuBurn { public static volatile float Sink; public static void Run() { double x=1.0; while(true) { x=Math.Sqrt(x+1.000001); if(x>1000.0) x=1.0; Sink=(float)x; } } }"
[CpuBurn]::Run()
"@
Set-Content -LiteralPath $workerPath -Value $workerScript -Encoding ASCII
$worker = $null
try {
  $worker = Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -WindowStyle Hidden -PassThru -ArgumentList "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$workerPath`""
  Start-Sleep -Seconds 2
  if ($worker.HasExited) { throw "CPU worker exited before sampling began." }

  $scheme = (powercfg /getactivescheme 2>&1 | Out-String).Trim()
  $services = Get-Service -Name dptftcs,ipfsvc -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)=$($_.Status)" }
  "Expected source: $expected"
  "Verified source: $(Get-PowerSource)"
  "Duration: $duration seconds"
  "Worker affinity: logical CPU 0"
  "Active power scheme: $scheme"
  "Intel DTT/IPF services: $($services -join ", ")"
  "Timestamp,CPU0Utility,CPU0Performance,CPU0FrequencyMHz,TotalCPUUtility,TotalCPUFrequencyMHz"

  $end = (Get-Date).AddSeconds($duration)
  while ((Get-Date) -lt $end) {
    if ($worker.HasExited) { throw "CPU worker exited during sampling." }
    $rows = Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue
    $cpu0 = $rows | Where-Object Name -eq "0,0" | Select-Object -First 1
    $total = $rows | Where-Object Name -eq "_Total" | Select-Object -First 1
    $now = Get-Date -Format o
    if ($cpu0 -and $total) {
      "$now,$($cpu0.PercentProcessorUtility),$($cpu0.PercentProcessorPerformance),$($cpu0.ProcessorFrequency),$($total.PercentProcessorUtility),$($total.ProcessorFrequency)"
    } else {
      "$now,unavailable,unavailable,unavailable,unavailable,unavailable"
    }
    Start-Sleep -Seconds 1
  }
} finally {
  if ($worker -and -not $worker.HasExited) { Stop-Process -Id $worker.Id -Force }
  Remove-Item -LiteralPath $workerPath -Force -ErrorAction SilentlyContinue
}
' | str replace 'EXPECTED_SOURCE' $expected_source | str replace 'DURATION_SECONDS' ($duration | into string)

  let result = (run-powershell $ps)
  let output = [$result.stdout, $result.stderr] | str join "\n" | str trim
  let capture_dir = ($env.TEMP | path join "speedometer-power-captures")
  mkdir $capture_dir
  let stamp = (date now | format date "%Y%m%dT%H%M%SZ")
  let log = ($capture_dir | path join $"($stamp)-cpu-load-windows-($expected_source).log")
  $output | save $log
  if $result.exit_code != 0 {
    print $output
    print $"Capture failed; details saved to ($log)."
    error make {msg: $"Windows capture failed (exit ($result.exit_code)); output saved to ($log)."}
  }
  print $output
  print $"Capture saved: ($log)"
}
