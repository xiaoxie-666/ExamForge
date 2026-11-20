[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JtlPath,
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $JtlPath -PathType Leaf)) { throw "JTL not found: $JtlPath" }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Split-Path -Parent (Resolve-Path -LiteralPath $JtlPath).Path
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$rows = @(Import-Csv -LiteralPath $JtlPath)
if ($rows.Count -eq 0) { throw 'JTL contains no samples.' }

# The full-flow plan has one internal JSR223 synchronization sample. It is not HTTP traffic.
$barrierLabel = '00 Barrier - all candidates started'
$controlRows = @($rows | Where-Object { $_.label -eq $barrierLabel })
$httpRows = @($rows | Where-Object { $_.label -ne $barrierLabel })
if ($httpRows.Count -eq 0) { throw 'JTL contains no HTTP samples.' }

function Get-NearestRankPercentile([double[]]$SortedValues, [double]$Percentile) {
    if ($SortedValues.Count -eq 0) { return 0 }
    $index = [Math]::Max(0, [Math]::Ceiling($SortedValues.Count * $Percentile) - 1)
    return [Math]::Round($SortedValues[$index], 2)
}

function Get-TimedRows([object[]]$InputRows) {
    return @($InputRows | Where-Object {
        $_.timeStamp -match '^\d+(\.\d+)?$' -and
        $_.elapsed -match '^\d+(\.\d+)?$'
    })
}

function Get-ObservedWindowSeconds([object[]]$InputRows) {
    $timed = @(Get-TimedRows -InputRows $InputRows)
    if ($timed.Count -eq 0) { return 0.0 }
    $starts = @($timed | ForEach-Object { [double]$_.timeStamp })
    $ends = @($timed | ForEach-Object { [double]$_.timeStamp + [double]$_.elapsed })
    $firstStart = ($starts | Measure-Object -Minimum).Minimum
    $lastEnd = ($ends | Measure-Object -Maximum).Maximum
    return [Math]::Max(0.0, (($lastEnd - $firstStart) / 1000.0))
}

$summary = @()
foreach ($group in ($httpRows | Group-Object -Property label | Sort-Object Name)) {
    $items = @($group.Group)
    $times = @(
        $items |
            Where-Object { $_.elapsed -match '^\d+(\.\d+)?$' } |
            ForEach-Object { [double]$_.elapsed } |
            Sort-Object
    )
    if ($times.Count -eq 0) { continue }

    $errors = @($items | Where-Object { $_.success -ne 'true' }).Count
    $avg = ($times | Measure-Object -Average).Average
    $requestWindow = Get-ObservedWindowSeconds -InputRows $items
    $requestTimedCount = @(Get-TimedRows -InputRows $items).Count
    $requestTps = if ($requestWindow -gt 0) { [Math]::Round(($requestTimedCount / $requestWindow), 2) } else { 0 }

    $summary += [PSCustomObject]@{
        Request = $group.Name
        Count = $items.Count
        Errors = $errors
        ErrorRatePct = [Math]::Round(($errors * 100.0 / $items.Count), 2)
        Avg_ms = [Math]::Round($avg, 2)
        P90_ms = (Get-NearestRankPercentile -SortedValues ([double[]]$times) -Percentile 0.90)
        P95_ms = (Get-NearestRankPercentile -SortedValues ([double[]]$times) -Percentile 0.95)
        P99_ms = (Get-NearestRankPercentile -SortedValues ([double[]]$times) -Percentile 0.99)
        Max_ms = [Math]::Round($times[-1], 2)
        ObservedTPS_req_s = $requestTps
    }
}

$allTimes = @(
    $httpRows |
        Where-Object { $_.elapsed -match '^\d+(\.\d+)?$' } |
        ForEach-Object { [double]$_.elapsed } |
        Sort-Object
)
if ($allTimes.Count -eq 0) { throw 'JTL contains no valid elapsed-time values.' }

$totalErrors = @($httpRows | Where-Object { $_.success -ne 'true' }).Count
$timedRows = @(Get-TimedRows -InputRows $httpRows)
$invalidTimingRows = $httpRows.Count - $timedRows.Count
$durationSeconds = Get-ObservedWindowSeconds -InputRows $httpRows
if ($durationSeconds -le 0) {
    throw 'Unable to calculate the HTTP sample window from JTL timeStamp and elapsed columns.'
}
$overallTps = [Math]::Round(($timedRows.Count / $durationSeconds), 2)
$overallAverage = [Math]::Round((($allTimes | Measure-Object -Average).Average), 2)
$overallP95 = Get-NearestRankPercentile -SortedValues ([double[]]$allTimes) -Percentile 0.95
$overallP99 = Get-NearestRankPercentile -SortedValues ([double[]]$allTimes) -Percentile 0.99
$overallMax = [Math]::Round($allTimes[-1], 2)
$errorRate = [Math]::Round(($totalErrors * 100.0 / $httpRows.Count), 2)

$csvOut = Join-Path $OutputDirectory 'summary.csv'
$txtOut = Join-Path $OutputDirectory 'summary.txt'
$summary | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8

$lines = @(
    'ExamForge JMeter Result Summary',
    ('JTL: {0}' -f (Resolve-Path -LiteralPath $JtlPath).Path),
    ('HTTP samples: {0}' -f $httpRows.Count),
    ('Internal barrier samples (not HTTP): {0}' -f $controlRows.Count),
    ('HTTP errors: {0}' -f $totalErrors),
    ('HTTP error rate: {0}%' -f $errorRate),
    ('Valid HTTP timing rows: {0}' -f $timedRows.Count),
    ('Rows excluded from throughput timing: {0}' -f $invalidTimingRows),
    ('Observed HTTP throughput: {0} requests/sec (approx.)' -f $overallTps),
    ('Observed HTTP sample window: {0} sec (first request start to last request end)' -f [Math]::Round($durationSeconds, 2)),
    ('Overall average response time: {0} ms' -f $overallAverage),
    ('Overall P95 response time: {0} ms' -f $overallP95),
    ('Overall P99 response time: {0} ms' -f $overallP99),
    ('Overall maximum response time: {0} ms' -f $overallMax),
    '',
    'Per-request HTTP metrics (nearest-rank percentiles; observed TPS is approximate):'
)
$lines += ($summary | Format-Table -AutoSize | Out-String -Width 240).TrimEnd()
$lines | Set-Content -LiteralPath $txtOut -Encoding UTF8

Write-Host ''
Write-Host '===== Overall HTTP performance summary =====' -ForegroundColor Cyan
[PSCustomObject]@{
    HttpSamples = $httpRows.Count
    Errors = $totalErrors
    ErrorRatePct = $errorRate
    ObservedTPS = $overallTps
    WindowSeconds = [Math]::Round($durationSeconds, 2)
    AverageMs = $overallAverage
    P95Ms = $overallP95
    P99Ms = $overallP99
} | Format-List
Write-Host '===== Per-request HTTP performance summary =====' -ForegroundColor Cyan
$summary | Format-Table -AutoSize
Write-Host "Saved: $csvOut"
Write-Host "Saved: $txtOut"
