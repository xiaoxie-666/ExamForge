[CmdletBinding()]
param(
    [ValidateSet('entry','steady','full')][string]$Plan = 'entry',
    # The default test scale is fixed at 1000 VUs. Smaller values remain available for smoke tests.
    [ValidateRange(1,1000)][int]$Threads = 1000,
    [ValidateRange(1001,2000)][int]$AccountStart = 1001,
    [ValidateRange(0,1000)][int]$AccountCount = 0,
    [ValidateRange(0,2147483647)][int]$ExamId = 0,
    [ValidateRange(1,3600)][int]$Ramp = 10,
    [ValidateRange(30,7200)][int]$HoldSeconds = 300,
    [ValidateRange(-1,1000)][int]$SyncGroupSize = -1,
    [ValidateRange(0,1000)][int]$StartGroupSize = 50,
    [ValidateRange(0,1000)][int]$SubmitGroupSize = 50,
    [ValidateRange(1000,3600000)][int]$SyncTimeout = 900000,
    [ValidateRange(0,5000)][int]$AnswerThinkTimeMs = 500,
    [ValidateRange(0,120000)][int]$AnswerStartJitterMs = 30000,
    [ValidateRange(100,60000)][int]$ThinkTimeMs = 5000,
    [ValidateRange(60,3600)][int]$GradingWaitSeconds = 1800,
    [string]$HostName = '127.0.0.1',
    [ValidateRange(1,65535)][int]$Port = 8080,
    [string]$JMeterPath = 'jmeter'
)

$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $packageRoot
. (Join-Path $projectRoot 'scripts/Import-ExamForgeEnv.ps1') -ProjectRoot $projectRoot
$DbName = if ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { 'examforge' }
$DbUser = if ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'examforge' }
$DbPassword = $env:MYSQL_PASSWORD
$LoadTestPassword = $env:LOADTEST_USER_PASSWORD
if ([string]::IsNullOrWhiteSpace($LoadTestPassword)) { throw 'LOADTEST_USER_PASSWORD is required in .env.' }
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw 'MYSQL_PASSWORD is required in .env.' }
$jmeterDir = Join-Path $packageRoot 'jmeter'
# Backward compatibility: also accept the original flat ZIP layout.
if (-not (Test-Path -LiteralPath $jmeterDir -PathType Container)) { $jmeterDir = $packageRoot }
$resultsRoot = Join-Path $packageRoot 'results'

if ($AccountCount -eq 0) { $AccountCount = $Threads }
if ($AccountCount -lt $Threads) { throw 'AccountCount must be greater than or equal to Threads.' }
if (($AccountStart + $AccountCount - 1) -gt 2000) { throw 'Account range exceeds loadtest2000.' }
if ($Plan -eq 'full' -and $AccountCount -ne $Threads) {
    throw 'For full flow, AccountCount must equal Threads so every virtual user receives one unique account.'
}
if ($Plan -eq 'steady' -and $HoldSeconds -lt 30) { throw 'HoldSeconds must be at least 30 seconds.' }

# Resolve the performance-test exam ID.
if ($ExamId -eq 0) {
    $examIdFile = Join-Path $packageRoot 'config\exam-id.txt'
    if (-not (Test-Path -LiteralPath $examIdFile)) {
        $projectExamIdFile = Join-Path (Split-Path -Parent $packageRoot) 'performance-test-exam-id.txt'
        if (Test-Path -LiteralPath $projectExamIdFile) { $examIdFile = $projectExamIdFile }
    }
    if (-not (Test-Path -LiteralPath $examIdFile)) {
        throw 'Exam ID was not supplied and config\exam-id.txt was not found. Pass -ExamId explicitly or create the performance test exam first.'
    }
    $examIdText = (Get-Content -LiteralPath $examIdFile -Raw).Trim()
    if ($examIdText -notmatch '^\d+$' -or [long]$examIdText -le 0) {
        throw "Invalid exam ID file: $examIdFile"
    }
    $ExamId = [int]$examIdText
}

# Resolve synchronization defaults.
$entrySyncGroupSize = 0
$resolvedStartGroupSize = $StartGroupSize
$resolvedSubmitGroupSize = $SubmitGroupSize
if ($SyncGroupSize -ge 0) {
    $entrySyncGroupSize = $SyncGroupSize
    $resolvedStartGroupSize = $SyncGroupSize
    $resolvedSubmitGroupSize = $SyncGroupSize
}
if ($resolvedStartGroupSize -gt $Threads) {
    throw "StartGroupSize ($resolvedStartGroupSize) cannot exceed Threads ($Threads). Use 0 for all users together."
}
if ($resolvedSubmitGroupSize -gt $Threads) {
    throw "SubmitGroupSize ($resolvedSubmitGroupSize) cannot exceed Threads ($Threads). Use 0 for all users together."
}

# Resolve JMeter executable; accepts a full path or a command on PATH.
$jmeterExe = $null
if (Test-Path -LiteralPath $JMeterPath -PathType Leaf) {
    $jmeterExe = (Resolve-Path -LiteralPath $JMeterPath).Path
} else {
    $jmeterCommand = Get-Command $JMeterPath -ErrorAction SilentlyContinue
    if ($jmeterCommand) {
        if ($jmeterCommand.Path) { $jmeterExe = $jmeterCommand.Path }
        elseif ($jmeterCommand.Source) { $jmeterExe = $jmeterCommand.Source }
    }
}
if (-not $jmeterExe) {
    throw "Cannot find JMeter '$JMeterPath'. Install JMeter 5.6.x and pass -JMeterPath with the full path to jmeter.bat."
}

$jmxName = switch ($Plan) {
    'entry'  { 'exam-entry.jmx' }
    'steady' { 'exam-steady.jmx' }
    'full'   { 'submit-flow.jmx' }
}
$jmxPath = Join-Path $jmeterDir $jmxName
if (-not (Test-Path -LiteralPath $jmxPath -PathType Leaf)) { throw "JMX plan not found: $jmxPath" }

# Generate one unique account row per virtual user. CSV intentionally has no header.
$csvPath = Join-Path $jmeterDir 'users.csv'
$csvLines = [System.Collections.Generic.List[string]]::new()
for ($i = $AccountStart; $i -lt ($AccountStart + $AccountCount); $i++) {
    $csvLines.Add(('loadtest{0:D4},{1},{2}' -f $i, $LoadTestPassword, $ExamId))
}
[System.IO.File]::WriteAllLines($csvPath, [string[]]$csvLines, [System.Text.UTF8Encoding]::new($false))

# Read-only API health preflight.
$healthUrl = "http://${HostName}:$Port/actuator/health"
try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 8 -UseBasicParsing
    if ($health.status -ne 'UP') { throw "API health status is '$($health.status)'" }
} catch {
    throw "API health check failed at $healthUrl. Start Docker Compose and verify the API first. Details: $($_.Exception.Message)"
}

# Full flow requires a live Worker and the complete event infrastructure for asynchronous grading.
if ($Plan -eq 'full') {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'docker-compose.yml'))) {
        throw 'Full-flow preflight requires this JMeter package to be directly under the ExamForge Docker Compose root.'
    }
    Push-Location $projectRoot
    try {
        $runningServices = @(& docker compose ps --services --status running)
        if ($LASTEXITCODE -ne 0) { throw 'Could not read Docker Compose service status.' }
        $requiredServices = @('api','worker','mysql','redis','broker','namesrv')
        $missingServices = @($requiredServices | Where-Object { $_ -notin $runningServices })
        if ($missingServices.Count -gt 0) {
            throw "Full flow requires these Compose services to be running: $($missingServices -join ', '). Start and verify them before testing."
        }

        $lastAccount = $AccountStart + $AccountCount - 1
        $accountQuery = "SELECT COUNT(*) FROM sys_user WHERE username REGEXP '^loadtest[0-9]+$' AND CAST(SUBSTRING(username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount AND role='STUDENT' AND status=1;"
        $availableAccounts = & docker compose exec -T -e "MYSQL_PWD=$DbPassword" mysql mysql --batch --skip-column-names "-u$DbUser" $DbName -e $accountQuery
        if ($LASTEXITCODE -ne 0) { throw 'Could not verify load-test accounts in MySQL.' }
        $availableAccountLine = @($availableAccounts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
        if ($availableAccountLine.Count -eq 0) { throw 'MySQL returned no load-test account count.' }
        $availableAccountCount = [int]$availableAccountLine[0].ToString().Trim()
        if ($availableAccountCount -ne $AccountCount) {
            throw "Expected $AccountCount enabled STUDENT accounts in the selected range, found $availableAccountCount."
        }

        $attemptQuery = "SELECT COUNT(*) FROM exam_attempt a JOIN sys_user u ON u.id=a.user_id WHERE a.exam_id=$ExamId AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount;"
        $existingAttempts = & docker compose exec -T -e "MYSQL_PWD=$DbPassword" mysql mysql --batch --skip-column-names "-u$DbUser" $DbName -e $attemptQuery
        if ($LASTEXITCODE -ne 0) { throw 'Could not verify prior attempts in MySQL; refusing to run a full-flow test.' }
        $existingAttemptLine = @($existingAttempts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
        if ($existingAttemptLine.Count -eq 0) { throw 'MySQL returned no existing-attempt count.' }
        $existingCount = [int]$existingAttemptLine[0].ToString().Trim()
        if ($existingCount -gt 0) {
            throw "This account range already has $existingCount attempt(s) for exam $ExamId. Full flow cannot reuse these one-time attempts. Use a fresh objective-only test exam or unused load-test accounts."
        }
    } finally {
        Pop-Location
    }
}

New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runName = '{0}-exam{1}-{2}users-{3}' -f $Plan, $ExamId, $Threads, $stamp
$runDir = Join-Path $resultsRoot $runName
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$jtlPath = Join-Path $runDir 'results.jtl'
$reportDir = Join-Path $runDir 'report'
$logPath = Join-Path $runDir 'jmeter.log'

$totalDuration = $Ramp + $HoldSeconds
$runInfo = @(
    "Plan=$Plan",
    "ExamId=$ExamId",
    "Threads=$Threads",
    "RampSeconds=$Ramp",
    "AccountStart=$AccountStart",
    "AccountCount=$AccountCount",
    "Host=$HostName",
    "Port=$Port",
    "JMeter=$jmeterExe",
    "JMX=$jmxPath",
    "StartedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)
if ($Plan -eq 'steady') {
    $runInfo += "HoldSeconds=$HoldSeconds"
    $runInfo += "TotalThreadGroupDurationSeconds=$totalDuration"
    $runInfo += "ThinkTimeMs=$ThinkTimeMs"
}
if ($Plan -eq 'full') {
    $runInfo += "StartGroupSize=$resolvedStartGroupSize"
    $runInfo += "SubmitGroupSize=$resolvedSubmitGroupSize"
    $runInfo += "AnswerThinkTimeMs=$AnswerThinkTimeMs"
    $runInfo += "GradingWaitSeconds=$GradingWaitSeconds"
    $runInfo += "AnswerStartJitterMs=$AnswerStartJitterMs"
    $runInfo += 'FailurePolicy=stoptest'
    $runInfo += 'AnswerBarrier=All successfully started candidates must reach the answer phase'
}
$runInfo | Set-Content -LiteralPath (Join-Path $runDir 'run-info.txt') -Encoding UTF8

Write-Host ''
Write-Host "Plan: $Plan | Exam ID: $ExamId | Threads: $Threads | Ramp-up: $Ramp sec" -ForegroundColor Cyan
Write-Host ("Accounts: loadtest{0:D4} .. loadtest{1:D4}" -f $AccountStart, ($AccountStart + $AccountCount - 1))
Write-Host "JTL: $jtlPath"
if ($Plan -eq 'entry') {
    Write-Host 'Entry behavior: login during ramp-up, then release all authenticated candidates together to browse the exam list.' -ForegroundColor Yellow
} elseif ($Plan -eq 'steady') {
    Write-Host "Steady behavior: one login per user; authenticated sessions remain active for $HoldSeconds sec and browse every $ThinkTimeMs ms." -ForegroundColor Yellow
    Write-Host "Thread-group duration: $totalDuration sec (ramp $Ramp + hold $HoldSeconds). No exam attempts are created." -ForegroundColor Yellow
} else {
    Write-Warning 'FULL FLOW WRITES TEST DATA. A fresh objective-only test exam and unused load-test accounts are required.'
    Write-Host "Full flow: login/browse -> start in groups of $resolvedStartGroupSize -> all-user answer barrier -> save each question -> submit in groups of $resolvedSubmitGroupSize -> verify submission -> verify asynchronous grades in MySQL." -ForegroundColor Yellow
}
Write-Host 'Failure policy: stop the test on the first failed HTTP request or assertion; no invalid-token request cascade.' -ForegroundColor Yellow

$jmeterArgs = @(
    '-n', '-t', $jmxPath,
    "-Jhost=$HostName", "-Jport=$Port", "-JdataFile=$csvPath",
    "-Jthreads=$Threads", "-Jramp=$Ramp",
    "-JsyncTimeout=$SyncTimeout",
    "-JanswerThinkTimeMs=$AnswerThinkTimeMs",
    "-JanswerStartJitterMs=$AnswerStartJitterMs",
    '-JconnectTimeout=10000', '-JresponseTimeout=60000',
    '-l', $jtlPath, '-e', '-o', $reportDir, '-j', $logPath
)
if ($Plan -eq 'entry') { $jmeterArgs += "-JsyncGroupSize=$entrySyncGroupSize" }
if ($Plan -eq 'full') {
    $jmeterArgs += "-JstartGroupSize=$resolvedStartGroupSize"
    $jmeterArgs += "-JsubmitGroupSize=$resolvedSubmitGroupSize"
}
if ($Plan -eq 'steady') {
    $jmeterArgs += "-JdurationSeconds=$totalDuration"
    $jmeterArgs += "-JthinkTimeMs=$ThinkTimeMs"
}

Write-Host "Starting JMeter: $jmeterExe" -ForegroundColor Cyan
& $jmeterExe @jmeterArgs
$jmeterExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $jtlPath -PathType Leaf)) {
    throw "JMeter did not create a JTL file (exit code $jmeterExitCode). Check $logPath."
}

$acceptanceIssues = [System.Collections.Generic.List[string]]::new()
$summaryScript = Join-Path $packageRoot 'summarize-results.ps1'
try {
    & $summaryScript -JtlPath $jtlPath -OutputDirectory $runDir
} catch {
    $acceptanceIssues.Add("Result summary failed: $($_.Exception.Message)")
}

$runRows = @()
try {
    $runRows = @(Import-Csv -LiteralPath $jtlPath)
} catch {
    $acceptanceIssues.Add("Unable to read JTL: $($_.Exception.Message)")
}

$barrierLabel = '00 Barrier - all candidates started'
$barrierRows = @($runRows | Where-Object { $_.label -eq $barrierLabel })
$httpRows = @($runRows | Where-Object { $_.label -ne $barrierLabel })
$httpErrors = @($httpRows | Where-Object { $_.success -ne 'true' }).Count
$barrierErrors = @($barrierRows | Where-Object { $_.success -ne 'true' }).Count

function Get-LabelSampleCount([object[]]$Rows, [string]$Label) {
    $matchingRows = @($Rows | Where-Object { $_.label -eq $Label })
    return $matchingRows.Count
}

if ($jmeterExitCode -ne 0) {
    $acceptanceIssues.Add("JMeter exited with code $jmeterExitCode. Inspect jmeter.log.")
}
if ($httpRows.Count -eq 0) {
    $acceptanceIssues.Add('No HTTP samples were recorded.')
}
if ($httpErrors -gt 0) {
    $acceptanceIssues.Add("HTTP errors/assertion failures: $httpErrors.")
}
if ($barrierErrors -gt 0) {
    $acceptanceIssues.Add("Answer-phase barrier failures: $barrierErrors.")
}

$loginCount = Get-LabelSampleCount -Rows $httpRows -Label '01 Login'
$browseLabel = if ($Plan -eq 'steady') { '02 Repeated browse available exams' } else { '02 Browse available exams' }
$browseCount = Get-LabelSampleCount -Rows $httpRows -Label $browseLabel
$startCount = Get-LabelSampleCount -Rows $httpRows -Label '03 Start exam'
$saveAnswerCount = Get-LabelSampleCount -Rows $httpRows -Label '04 Save answer'
$submitCount = Get-LabelSampleCount -Rows $httpRows -Label '05 Submit exam'
$verifyAttemptCount = Get-LabelSampleCount -Rows $httpRows -Label '06 Verify submitted attempt'

switch ($Plan) {
    'entry' {
        if ($loginCount -ne $Threads) { $acceptanceIssues.Add("Login samples expected=$Threads, actual=$loginCount.") }
        if ($browseCount -ne $Threads) { $acceptanceIssues.Add("Exam-list samples expected=$Threads, actual=$browseCount.") }
    }
    'steady' {
        if ($loginCount -ne $Threads) { $acceptanceIssues.Add("Login samples expected=$Threads, actual=$loginCount.") }
        if ($browseCount -lt $Threads) { $acceptanceIssues.Add("Repeated exam-list samples must be at least $Threads, actual=$browseCount.") }
    }
    'full' {
        if ($loginCount -ne $Threads) { $acceptanceIssues.Add("Login samples expected=$Threads, actual=$loginCount.") }
        if ($browseCount -ne $Threads) { $acceptanceIssues.Add("Exam-list samples expected=$Threads, actual=$browseCount.") }
        if ($startCount -ne $Threads) { $acceptanceIssues.Add("Start-exam samples expected=$Threads, actual=$startCount.") }
        if ($submitCount -ne $Threads) { $acceptanceIssues.Add("Submit samples expected=$Threads, actual=$submitCount.") }
        if ($verifyAttemptCount -ne $Threads) { $acceptanceIssues.Add("Attempt-verification samples expected=$Threads, actual=$verifyAttemptCount.") }
        if ($barrierRows.Count -ne $Threads) { $acceptanceIssues.Add("Answer-phase barrier samples expected=$Threads, actual=$($barrierRows.Count).") }
    }
}

$databaseVerification = 'NOT_REQUIRED'
if ($Plan -eq 'full' -and $acceptanceIssues.Count -eq 0) {
    $databaseVerification = 'RUNNING'
    try {
        $verifyScript = Join-Path $packageRoot 'verify-full-run.ps1'
        & $verifyScript -ExamId $ExamId -AccountStart $AccountStart -AccountCount $AccountCount -TimeoutSeconds $GradingWaitSeconds -RunDirectory $runDir

        $verificationCsv = Join-Path $runDir 'verification.csv'
        if (-not (Test-Path -LiteralPath $verificationCsv -PathType Leaf)) {
            throw 'Database verification did not produce verification.csv.'
        }
        $verification = Import-Csv -LiteralPath $verificationCsv | Select-Object -First 1
        if ($null -eq $verification) { throw 'Database verification CSV is empty.' }

        $expectedAnswerRequests = $Threads * [int]$verification.PaperQuestions
        if ($saveAnswerCount -ne $expectedAnswerRequests) {
            throw "Save-answer HTTP samples expected=$expectedAnswerRequests, actual=$saveAnswerCount."
        }
        $databaseVerification = 'PASS'
    } catch {
        $databaseVerification = 'FAIL'
        $acceptanceIssues.Add("Full-flow database verification failed: $($_.Exception.Message)")
    }
} elseif ($Plan -eq 'full') {
    $databaseVerification = 'SKIPPED_DUE_TO_JMETER_FAILURE'
}

$acceptancePath = Join-Path $runDir 'acceptance.txt'
$acceptanceLines = @(
    'ExamForge JMeter Acceptance',
    "Plan=$Plan",
    "ExamId=$ExamId",
    "Threads=$Threads",
    "JMeterExitCode=$jmeterExitCode",
    "HttpSamples=$($httpRows.Count)",
    "HttpErrors=$httpErrors",
    "LoginSamples=$loginCount",
    "ExamListSamples=$browseCount",
    "StartExamSamples=$startCount",
    "SaveAnswerSamples=$saveAnswerCount",
    "SubmitSamples=$submitCount",
    "VerifyAttemptSamples=$verifyAttemptCount",
    "BarrierSamples=$($barrierRows.Count)",
    "BarrierErrors=$barrierErrors",
    "DatabaseVerification=$databaseVerification",
    "FinishedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)
if ($acceptanceIssues.Count -eq 0) {
    $acceptanceLines += 'RESULT=PASS'
} else {
    $acceptanceLines += 'RESULT=FAIL'
    $acceptanceLines += 'Issues:'
    foreach ($issue in $acceptanceIssues) { $acceptanceLines += "- $issue" }
}
$acceptanceLines | Set-Content -LiteralPath $acceptancePath -Encoding UTF8

Write-Host ''
if ($acceptanceIssues.Count -gt 0) {
    Write-Host 'RESULT=FAIL' -ForegroundColor Red
    foreach ($issue in $acceptanceIssues) { Write-Host " - $issue" -ForegroundColor Red }
    Write-Host "Partial results: $runDir" -ForegroundColor Yellow
    throw "Load test did not pass acceptance. See $acceptancePath and the JMeter log."
}

Write-Host 'RESULT=PASS' -ForegroundColor Green
Write-Host "Acceptance: $acceptancePath" -ForegroundColor Green
Write-Host "HTML report: $reportDir\index.html" -ForegroundColor Green
Write-Host "Summary: $runDir\summary.txt" -ForegroundColor Green
