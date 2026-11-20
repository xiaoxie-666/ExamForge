[CmdletBinding()]
param(
    [ValidateRange(10,7200)][int]$DurationSeconds = 1800,
    [ValidateRange(1,60)][int]$IntervalSeconds = 5,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$expectedContainers = @(
    'examforge-api',
    'examforge-worker',
    'examforge-mysql',
    'examforge-redis',
    'examforge-broker',
    'examforge-namesrv',
    'examforge-xxl-admin',
    'examforge-web'
)

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $results = Join-Path $PSScriptRoot 'results'
    New-Item -ItemType Directory -Force -Path $results | Out-Null
    $OutputPath = Join-Path $results ('resource-monitor-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
} else {
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
}

function Get-HostSnapshot {
    $result = [PSCustomObject]@{
        CPUPercent = $null
        FreeMemoryGB = $null
        TotalMemoryGB = $null
    }

    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop |
            Where-Object { $null -ne $_.LoadPercentage })
        if ($processors.Count -gt 0) {
            $cpuValues = @($processors | ForEach-Object { [double]$_.LoadPercentage })
            $result.CPUPercent = [Math]::Round((($cpuValues | Measure-Object -Average).Average), 2)
        }
    } catch {
        # Host CPU is supplementary; Docker collection continues if WMI is unavailable.
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $result.TotalMemoryGB = [Math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
        $result.FreeMemoryGB = [Math]::Round(([double]$os.FreePhysicalMemory / 1MB), 2)
    } catch {
        # Leave memory values blank if Windows does not return the CIM data.
    }
    return $result
}

function Get-JMeterProcessList {
    try {
        return @(
            Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
                Where-Object {
                    $_.Name -match '^javaw?\.exe$' -and
                    $_.CommandLine -match 'org\.apache\.jmeter|ApacheJMeter'
                }
        )
    } catch {
        return @()
    }
}

$records = [System.Collections.Generic.List[object]]::new()
$previousJMeterCpu = @{}
$endAt = (Get-Date).AddSeconds($DurationSeconds)
$sampleNumber = 0

Write-Host "Monitoring ExamForge Docker + Windows + JMeter for $DurationSeconds seconds." -ForegroundColor Cyan
Write-Host "Expected containers: $($expectedContainers -join ', ')"
Write-Host "CSV output: $OutputPath"

while ((Get-Date) -lt $endAt) {
    $sampleAt = Get-Date
    $stamp = $sampleAt.ToString('yyyy-MM-dd HH:mm:ss.fff')
    $sampleNumber++

    # Read all container states so stopped/missing services are visible in the CSV.
    $statusLines = @(& docker ps -a --format '{{.Names}}|{{.Status}}' 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'docker ps failed. Check that Docker Desktop is running.'
    }
    $statusMap = @{}
    foreach ($line in $statusLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|', 2
        if ($parts.Count -eq 2) { $statusMap[$parts[0]] = $parts[1] }
    }

    # Collect one snapshot of every running container, then retain the ExamForge services.
    $statsLines = @(& docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' 2>$null)
    $statsExitCode = $LASTEXITCODE
    if ($statsExitCode -ne 0) {
        Write-Warning 'docker stats returned an error during this sample; container status and host metrics will still be recorded.'
        $statsLines = @()
    }
    $statsMap = @{}
    foreach ($line in $statsLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|', 7
        if ($parts.Count -eq 7) { $statsMap[$parts[0]] = $parts }
    }

    if ($statsExitCode -ne 0) {
        $records.Add([PSCustomObject]@{
            Timestamp = $stamp; RecordType = 'DockerStatsError'; Name = 'docker stats'; Status = 'Unavailable for this sample';
            CPUPercent = $null; MemoryUsage = $null; MemoryPercent = $null; NetworkIO = $null; BlockIO = $null; PIDs = $null;
            HostCPUPercent = $null; HostFreeMemoryGB = $null; HostTotalMemoryGB = $null; JMeterPID = $null;
            JMeterCPUPercent = $null; JMeterWorkingSetMB = $null; JMeterProcessCount = $null
        })
    }

    foreach ($container in $expectedContainers) {
        if ($statsMap.ContainsKey($container)) {
            $parts = $statsMap[$container]
            $status = 'Running'
            $cpu = $parts[1]
            $memory = $parts[2]
            $memoryPct = $parts[3]
            $networkIO = $parts[4]
            $blockIO = $parts[5]
            $pids = $parts[6]
        } else {
            $status = if ($statusMap.ContainsKey($container)) { $statusMap[$container] } else { 'NotFound' }
            $cpu = $null
            $memory = $null
            $memoryPct = $null
            $networkIO = $null
            $blockIO = $null
            $pids = $null
        }

        $records.Add([PSCustomObject]@{
            Timestamp = $stamp
            RecordType = 'DockerContainer'
            Name = $container
            Status = $status
            CPUPercent = $cpu
            MemoryUsage = $memory
            MemoryPercent = $memoryPct
            NetworkIO = $networkIO
            BlockIO = $blockIO
            PIDs = $pids
            HostCPUPercent = $null
            HostFreeMemoryGB = $null
            HostTotalMemoryGB = $null
            JMeterPID = $null
            JMeterCPUPercent = $null
            JMeterWorkingSetMB = $null
            JMeterProcessCount = $null
        })
    }

    $hostSnapshot = Get-HostSnapshot
    $jmeterProcesses = @(Get-JMeterProcessList)
    $records.Add([PSCustomObject]@{
        Timestamp = $stamp
        RecordType = 'WindowsHost'
        Name = 'WindowsHost'
        Status = 'Sampled'
        CPUPercent = $null
        MemoryUsage = $null
        MemoryPercent = $null
        NetworkIO = $null
        BlockIO = $null
        PIDs = $null
        HostCPUPercent = $hostSnapshot.CPUPercent
        HostFreeMemoryGB = $hostSnapshot.FreeMemoryGB
        HostTotalMemoryGB = $hostSnapshot.TotalMemoryGB
        JMeterPID = $null
        JMeterCPUPercent = $null
        JMeterWorkingSetMB = $null
        JMeterProcessCount = $jmeterProcesses.Count
    })

    foreach ($jmeterProcess in $jmeterProcesses) {
        $pidValue = [int]$jmeterProcess.ProcessId
        $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }

        $cpuPercent = $null
        $cpuSeconds = $null
        try { $cpuSeconds = [double]$process.CPU } catch { }
        if ($null -ne $cpuSeconds -and $previousJMeterCpu.ContainsKey($pidValue)) {
            $previous = $previousJMeterCpu[$pidValue]
            $elapsed = ($sampleAt - $previous.SampleAt).TotalSeconds
            if ($elapsed -gt 0 -and $cpuSeconds -ge $previous.CpuSeconds) {
                $cpuPercent = [Math]::Round((($cpuSeconds - $previous.CpuSeconds) / $elapsed / [Environment]::ProcessorCount) * 100.0, 2)
            }
        }
        if ($null -ne $cpuSeconds) {
            $previousJMeterCpu[$pidValue] = [PSCustomObject]@{
                CpuSeconds = $cpuSeconds
                SampleAt = $sampleAt
            }
        }

        $records.Add([PSCustomObject]@{
            Timestamp = $stamp
            RecordType = 'JMeterProcess'
            Name = $process.ProcessName
            Status = 'Running'
            CPUPercent = $null
            MemoryUsage = $null
            MemoryPercent = $null
            NetworkIO = $null
            BlockIO = $null
            PIDs = $null
            HostCPUPercent = $null
            HostFreeMemoryGB = $null
            HostTotalMemoryGB = $null
            JMeterPID = $pidValue
            JMeterCPUPercent = $cpuPercent
            JMeterWorkingSetMB = [Math]::Round(($process.WorkingSet64 / 1MB), 2)
            JMeterProcessCount = $null
        })
    }

    Write-Progress -Activity 'ExamForge resource monitoring' -Status "Sample $sampleNumber | $stamp | JMeter processes: $($jmeterProcesses.Count)" -PercentComplete ([Math]::Min(100, (($DurationSeconds - [Math]::Max(0, ($endAt - (Get-Date)).TotalSeconds)) / $DurationSeconds) * 100))
    Start-Sleep -Seconds $IntervalSeconds
}

if ($records.Count -eq 0) { throw 'No resource records were collected.' }
$records | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
Write-Progress -Activity 'ExamForge resource monitoring' -Completed
Write-Host "Resource monitoring saved: $OutputPath" -ForegroundColor Green
Write-Host "Records: $($records.Count); samples: $sampleNumber; expected containers: $($expectedContainers.Count)" -ForegroundColor Green
