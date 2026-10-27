#!/usr/bin/env nu

def run-powershell [script: string] {
  ^powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $script | complete
}

def append-output [file: string, title: string, result: record] {
  let text = $"\n--- ($title) ---\n(($result.stdout | str trim))\n(($result.stderr | str trim))\nExit code: ($result.exit_code)\n"
  $text | save --append $file
}

def snapshot [file: string, label: string] {
  let ps = '
$ErrorActionPreference = "Continue"
"Timestamp: $(Get-Date -Format o)"
"Computer: $env:COMPUTERNAME"
"Windows: $((Get-CimInstance Win32_OperatingSystem).Caption) / $((Get-CimInstance Win32_OperatingSystem).Version)"
"Power source and battery:"
Get-CimInstance -Namespace root/WMI -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object PowerOnline,Charging,Discharging,RemainingCapacity | Format-List
Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object Name,BatteryStatus,EstimatedChargeRemaining,DesignCapacity,FullChargeCapacity | Format-List
"Active power scheme:"
powercfg /getactivescheme
"AC/DC processor power policy:"
powercfg /query SCHEME_CURRENT SUB_PROCESSOR
"Available power plans:"
powercfg /list
"Intel DTT/IPF services:"
Get-Service -Name dptftcs,ipfsvc -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType | Format-Table -AutoSize
"Processor:"
Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,CurrentClockSpeed,MaxClockSpeed | Format-List
"GPU adapters:"
Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate | Format-List
'
  let result = (run-powershell $ps)
  append-output $file $"($label) Windows snapshot" $result
}

def main [expected_source: string, duration: int = 240] {
  if ($expected_source not-in ["ac", "battery"]) {
    error make {msg: "Usage: nu scripts/capture-windows.nu ac|battery [duration-seconds]"}
  }
  let host_name = (sys host | get name | str downcase)
  if not ($host_name | str contains "windows") {
    error make {msg: "Run this script in Nushell on Windows."}
  }
  let source_check = (run-powershell '
$b = Get-CimInstance -Namespace root/WMI -ClassName BatteryStatus -ErrorAction SilentlyContinue
if ($b.PowerOnline -contains $true) { "ac" }
elseif ($b.Discharging -contains $true) { "battery" }
else { "unknown" }
')
  let actual_source = ($source_check.stdout | str trim | lines | last)
  if $actual_source != $expected_source {
    error make {msg: $"Expected ($expected_source), Windows battery telemetry reports ($actual_source). Capture stopped."}
  }
  let capture_dir = ($env.TEMP? | default '.') | path join 'speedometer-power-captures'
  mkdir $capture_dir
  let stamp = (date now | format date '%Y%m%dT%H%M%SZ')
  let log = ($capture_dir | path join $"($stamp)-windows-($expected_source).log")
  $"Expected power source: ($expected_source)\nCapture duration: ($duration) seconds\n" | save $log
  snapshot $log "before"
  print $"Writing to ($log). Start Speedometer now; CPU and GPU telemetry runs for ($duration) seconds."
  "Timestamp,CPUUtility,CPUPerformance,CPUFrequencyMHz,PercentMaxFrequency,PerformanceLimitFlags,GPU3DEngineUtilizationSum\n" | save --append $log
  let telemetry_template = '
$ErrorActionPreference = "Continue"
$end = (Get-Date).AddSeconds(%DURATION%)
while ((Get-Date) -lt $end) {
  $now = Get-Date -Format o
  $cpu = Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue | Where-Object Name -eq "_Total" | Select-Object -First 1
  $gpu = Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "engtype_3D" } | Measure-Object -Property UtilizationPercentage -Sum
  [pscustomobject]@{Timestamp=$now; CPUUtility=$cpu.PercentProcessorUtility; CPUPerformance=$cpu.PercentProcessorPerformance; CPUFrequencyMHz=$cpu.ProcessorFrequency; PercentMaxFrequency=$cpu.PercentofMaximumFrequency; PerformanceLimitFlags=$cpu.PerformanceLimitFlags; GPU3DEngineUtilizationSum=$gpu.Sum} | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1
  Start-Sleep -Seconds 1
}
'
  let telemetry = ($telemetry_template | str replace '%DURATION%' ($duration | into string))
  let samples = (run-powershell $telemetry)
  append-output $log "1-second CPU/GPU performance samples" $samples
  snapshot $log "after"
  let score = (input "Speedometer score (Enter to leave blank): ")
  $"\nRecorded Speedometer score: (($score | str trim | default 'not provided'))\n" | save --append $log
  print $"Capture saved: ($log)"
}
