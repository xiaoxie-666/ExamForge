[CmdletBinding()]
param(
    [int]$SourceExamId = 0,

    [ValidatePattern('^loadtest[0-9]{4}$')]
    [string]$Username = 'loadtest1001',

    [string]$Password = '',

    [string]$ApiBaseUrl = 'http://localhost:8080',

    [string]$DbName = '',
    [string]$DbUser = '',
    [string]$DbPassword = '',

    [ValidateRange(30, 600)]
    [int]$VerifyTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'scripts/Import-ExamForgeEnv.ps1') -ProjectRoot $projectRoot
if ([string]::IsNullOrWhiteSpace($DbName)) { $DbName = if ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { 'examforge' } }
if ([string]::IsNullOrWhiteSpace($DbUser)) { $DbUser = if ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'examforge' } }
if ([string]::IsNullOrWhiteSpace($DbPassword)) { $DbPassword = $env:MYSQL_PASSWORD }
if ([string]::IsNullOrWhiteSpace($Password)) { $Password = $env:LOADTEST_USER_PASSWORD }
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw 'MYSQL_PASSWORD is required in .env.' }
if ([string]::IsNullOrWhiteSpace($Password)) { throw 'LOADTEST_USER_PASSWORD is required in .env.' }
$ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$resultDirectory = Join-Path $projectRoot 'ExamForge_JMeter_Performance\results'
$resultPath = Join-Path $resultDirectory "outbox-recovery-$stamp.txt"
$overrideFile = Join-Path $projectRoot ("docker-compose.outbox-recovery-test-{0}.yml" -f $PID)
$restoreNeeded = $false
$report = New-Object 'System.Collections.Generic.List[string]'
$testExamId = 0
$attemptId = 0

function Add-ReportLine {
    param([string]$Line)
    $report.Add($Line)
    Write-Host $Line
}

function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & docker compose @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($output) {
        foreach ($line in $output) {
            Write-Host $line
        }
    }
    if ($exitCode -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Invoke-MySql {
    param([Parameter(Mandatory = $true)][string]$Sql)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & docker compose exec -T -e "MYSQL_PWD=$DbPassword" mysql mysql `
            --batch --raw --skip-column-names "-u$DbUser" $DbName -e $Sql 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        throw "MySQL query failed (exit code $exitCode). $details"
    }

    $cleanLines = @(
        $output |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ -ne '' -and $_ -notmatch '^mysql:' }
    )
    if ($cleanLines.Count -eq 0) { return '' }
    return [string]$cleanLines[-1]
}

function Wait-ApiHealthy {
    param([int]$TimeoutSeconds = 120)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $healthUrl = "$ApiBaseUrl/actuator/health"
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5 -UseBasicParsing
            if ($health.status -eq 'UP') {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 2
        }
        Start-Sleep -Milliseconds 500
    }
    throw "API did not become healthy within $TimeoutSeconds seconds: $healthUrl"
}

function Get-TestState {
    param([long]$Attempt)

    $sql = @"
SELECT CONCAT(
  COALESCE((SELECT status FROM outbox_event WHERE event_key='GRADE:$Attempt' LIMIT 1),'MISSING'),'|',
  COALESCE((SELECT status FROM outbox_event WHERE event_key='TIMEOUT:$Attempt' LIMIT 1),'MISSING'),'|',
  COALESCE((SELECT status FROM grade_result WHERE attempt_id=$Attempt LIMIT 1),'MISSING'),'|',
  (SELECT COUNT(*) FROM grade_result WHERE attempt_id=$Attempt),'|',
  (SELECT COUNT(*) FROM answer_record WHERE attempt_id=$Attempt),'|',
  COALESCE((SELECT status FROM exam_attempt WHERE id=$Attempt LIMIT 1),'MISSING')
);
"@
    $row = Invoke-MySql -Sql $sql
    if ([string]::IsNullOrWhiteSpace($row)) {
        throw "Could not read Outbox test state for attempt $Attempt."
    }
    return $row
}

function Get-WorkerSuccessCount {
    param([long]$Attempt)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $logs = & docker compose logs --since=10m worker 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        return 0
    }
    $allLogs = ($logs | ForEach-Object { $_.ToString() }) -join "`n"
    $pattern = 'Exam event consumed successfully: eventKey=GRADE:' + [regex]::Escape([string]$Attempt) + ','
    $matches = [regex]::Matches($allLogs, $pattern)
    return $matches.Count
}

function Wait-ForRecoveredGrade {
    param(
        [long]$Attempt,
        [int]$TimeoutSeconds,
        [int]$ExpectedAnswerRecords,
        [int]$MinimumConsumerSuccesses = 1
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = ''
    $lastConsumerCount = 0
    while ((Get-Date) -lt $deadline) {
        $lastState = Get-TestState -Attempt $Attempt
        $parts = $lastState.Split('|')
        $lastConsumerCount = Get-WorkerSuccessCount -Attempt $Attempt

        if ($parts.Count -ge 6 -and
            $parts[0] -eq 'SENT' -and
            $parts[1] -eq 'SENT' -and
            $parts[2] -eq 'COMPLETED' -and
            [int]$parts[3] -eq 1 -and
            [int]$parts[4] -eq $ExpectedAnswerRecords -and
            $parts[5] -eq 'SUBMITTED' -and
            $lastConsumerCount -ge $MinimumConsumerSuccesses) {
            return [pscustomobject]@{
                State = $lastState
                ConsumerSuccessCount = $lastConsumerCount
            }
        }
        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for Outbox recovery. LastState='$lastState'; worker GRADE success count=$lastConsumerCount."
}

Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'docker-compose.yml'))) {
        throw "docker-compose.yml was not found under $projectRoot"
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI was not found. Install/start Docker Desktop first.'
    }

    if ($SourceExamId -lt 0) { throw 'SourceExamId cannot be negative.' }
    if ($SourceExamId -eq 0) {
        $examIdFile = Join-Path $projectRoot 'performance-test-exam-id.txt'
        if (-not (Test-Path -LiteralPath $examIdFile)) {
            $examIdFile = Join-Path $projectRoot 'ExamForge_JMeter_Performance\config\exam-id.txt'
        }
        if (-not (Test-Path -LiteralPath $examIdFile)) {
            throw 'SourceExamId was not supplied and no performance-test exam ID file was found.'
        }
        $examIdText = (Get-Content -LiteralPath $examIdFile -Raw).Trim()
        if ($examIdText -notmatch '^\d+$' -or [int]$examIdText -le 0) {
            throw "Invalid source exam ID in $examIdFile"
        }
        $SourceExamId = [int]$examIdText
    }

    Add-ReportLine 'ExamForge Outbox recovery and consumer-idempotency test'
    Add-ReportLine "StartedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-ReportLine "SourceExamId=$SourceExamId"
    Add-ReportLine "Username=$Username"
    Add-ReportLine "API=$ApiBaseUrl"
    Add-ReportLine 'Existing exam attempts and the previous 1000-user JMeter results will not be deleted or modified.'

    # Confirm that the source exam is objective-only and that the isolated account is usable.
    $accountCount = Invoke-MySql -Sql "SELECT COUNT(*) FROM sys_user WHERE username='$Username' AND role='STUDENT' AND status=1;"
    if ([int]$accountCount -ne 1) {
        throw "Student account '$Username' does not exist or is disabled."
    }

    $sourceStats = Invoke-MySql -Sql @"
SELECT CONCAT(COUNT(*),'|',COALESCE(SUM(q.type='SUBJECTIVE'),0))
FROM exam_question eq
JOIN question_bank q ON q.id=eq.question_id
WHERE eq.exam_id=$SourceExamId;
"@
    if ([string]::IsNullOrWhiteSpace($sourceStats)) {
        throw "Could not inspect source exam $SourceExamId."
    }
    $sourceParts = $sourceStats.Split('|')
    if ($sourceParts.Count -ne 2 -or [int]$sourceParts[0] -lt 1 -or [int]$sourceParts[1] -ne 0) {
        throw "Source exam $SourceExamId must contain at least one question and no subjective questions. Found '$sourceStats'."
    }
    Add-ReportLine "SourceExamQuestions=$($sourceParts[0]); SubjectiveQuestions=$($sourceParts[1])"

    # Temporarily slow the API's scheduled Outbox publisher. The first scheduled scan
    # runs on startup; after the initial wait, the test has a 10-minute quiet window.
    $overrideContent = @'
services:
  api:
    environment:
      JAVA_TOOL_OPTIONS: "-Duser.timezone=Asia/Shanghai -Dexamforge.outbox.publish-interval-ms=600000"
'@
    [System.IO.File]::WriteAllText($overrideFile, $overrideContent, ([System.Text.UTF8Encoding]::new($false)))

    $restoreNeeded = $true
    Add-ReportLine 'Step 1/7: Restart API with a temporary 10-minute Outbox polling interval.'
    Invoke-Compose -Arguments @('-f', 'docker-compose.yml', '-f', $overrideFile, 'up', '-d', '--no-deps', '--force-recreate', 'api')
    Wait-ApiHealthy -TimeoutSeconds 150
    Start-Sleep -Seconds 8
    Add-ReportLine 'API is healthy; the startup Outbox scan has completed.'

    # Create a fresh exam by copying the objective-only source exam. This avoids
    # touching the completed exam 11 attempts used by the 1000-user test.
    $testTitle = "OutboxRecovery-$stamp-$PID"
    $createExamSql = @"
SET @source_exam_id = $SourceExamId;
SET @test_title = '$testTitle';
INSERT INTO exam (title,description,status,start_time,end_time,duration_minutes,created_by,create_time,update_time)
SELECT @test_title, CONCAT('Isolated Outbox recovery test cloned from exam ',id), 'PUBLISHED',
       DATE_SUB(NOW(),INTERVAL 5 MINUTE), DATE_ADD(NOW(),INTERVAL 1 DAY), 60,
       created_by, NOW(), NOW()
FROM exam WHERE id=@source_exam_id;
SET @new_exam_id = LAST_INSERT_ID();
INSERT INTO exam_question (exam_id,question_id,sort_order,score)
SELECT @new_exam_id,question_id,sort_order,score
FROM exam_question WHERE exam_id=@source_exam_id;
SELECT CONCAT(@new_exam_id,'|',(SELECT COUNT(*) FROM exam_question WHERE exam_id=@new_exam_id));
"@
    $createLine = Invoke-MySql -Sql $createExamSql
    if ($createLine -notmatch '^\d+\|\d+$') {
        throw "Could not create isolated Outbox test exam. MySQL output: $createLine"
    }
    $createParts = $createLine.Split('|')
    $testExamId = [int]$createParts[0]
    $testQuestionCount = [int]$createParts[1]
    if ($testExamId -le 0 -or $testQuestionCount -ne [int]$sourceParts[0]) {
        throw "Isolated exam creation was incomplete. ExamId=$testExamId; Questions=$testQuestionCount"
    }
    Add-ReportLine "Step 2/7: Created isolated exam $testExamId with $testQuestionCount objective questions."

    # Login, start, and submit one attempt. This writes TIMEOUT and GRADE Outbox
    # rows through the real transactional business methods.
    $loginBody = @{ username = $Username; password = $Password } | ConvertTo-Json -Compress
    $login = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/api/auth/login" `
        -ContentType 'application/json' -Body $loginBody -TimeoutSec 20 -UseBasicParsing
    if ($login.code -ne 0 -or -not $login.data.token) {
        throw "Login failed for $Username. API response: $($login | ConvertTo-Json -Depth 6 -Compress)"
    }
    $headers = @{ Authorization = "Bearer $($login.data.token)" }

    $started = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/api/candidate/exams/$testExamId/start" `
        -Headers $headers -TimeoutSec 30 -UseBasicParsing
    if ($started.code -ne 0 -or -not $started.data.attemptId) {
        throw "Could not start isolated exam. API response: $($started | ConvertTo-Json -Depth 6 -Compress)"
    }
    $attemptId = [long]$started.data.attemptId

    $submitted = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/api/candidate/attempts/$attemptId/submit" `
        -Headers $headers -TimeoutSec 30 -UseBasicParsing
    if ($submitted.code -ne 0) {
        throw "Could not submit isolated attempt $attemptId. API response: $($submitted | ConvertTo-Json -Depth 6 -Compress)"
    }
    Add-ReportLine "Step 3/7: Created and submitted isolated attempt $attemptId through the real API."

    Start-Sleep -Seconds 2
    $pendingState = Get-TestState -Attempt $attemptId
    $pendingParts = $pendingState.Split('|')
    if ($pendingParts.Count -lt 6 -or $pendingParts[0] -ne 'PENDING' -or $pendingParts[1] -ne 'PENDING') {
        throw "Expected both Outbox rows to remain PENDING while the publisher is paused. Actual state: $pendingState. Check whether the temporary polling interval took effect."
    }
    Add-ReportLine "Step 4/7: Confirmed GRADE and TIMEOUT Outbox rows are PENDING: $pendingState"

    # Fault injection: simulate API termination after claiming GRADE but before
    # successfully publishing it. recoverStuck() should release it after 2 minutes.
    $faultInjection = Invoke-MySql -Sql @"
UPDATE outbox_event
SET status='SENDING',
    update_time=DATE_SUB(NOW(),INTERVAL 3 MINUTE),
    last_error='SIMULATED_CRASH_AFTER_CLAIM'
WHERE event_key='GRADE:$attemptId' AND status='PENDING';
SELECT ROW_COUNT();
"@
    if ([int]$faultInjection -ne 1) {
        throw "Could not inject stale SENDING state for GRADE:$attemptId."
    }
    Add-ReportLine 'Step 5/7: Injected a stale SENDING state (3 minutes old) to simulate a publisher crash after claim.'

    # Remove the override and force API recreation with the normal 1-second default.
    Remove-Item -LiteralPath $overrideFile -Force -ErrorAction SilentlyContinue
    Invoke-Compose -Arguments @('-f', 'docker-compose.yml', 'up', '-d', '--no-deps', '--force-recreate', 'api')
    Wait-ApiHealthy -TimeoutSeconds 150
    $restoreNeeded = $false
    Add-ReportLine 'Step 6/7: Restarted API with the normal Outbox schedule; waiting for stale SENDING recovery and grading.'

    $firstRecovery = Wait-ForRecoveredGrade -Attempt $attemptId -TimeoutSeconds $VerifyTimeoutSeconds `
        -ExpectedAnswerRecords $testQuestionCount -MinimumConsumerSuccesses 1
    Add-ReportLine "RecoveredState=$($firstRecovery.State)"
    Add-ReportLine "WorkerGradeSuccessCountAfterRecovery=$($firstRecovery.ConsumerSuccessCount)"

    # Fault injection: republish the same business event. The consumer must treat
    # it as a duplicate and keep exactly one grade_result row.
    $duplicateReset = Invoke-MySql -Sql @"
UPDATE outbox_event
SET status='PENDING',
    published_at=NULL,
    next_retry_at=NOW(),
    last_error='SIMULATED_DUPLICATE_PUBLISH',
    update_time=NOW()
WHERE event_key='GRADE:$attemptId' AND status='SENT';
SELECT ROW_COUNT();
"@
    if ([int]$duplicateReset -ne 1) {
        throw "Could not queue the duplicate GRADE event for attempt $attemptId."
    }

    $duplicateDeadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
    $duplicateState = ''
    $duplicateConsumerCount = 0
    while ((Get-Date) -lt $duplicateDeadline) {
        $duplicateState = Get-TestState -Attempt $attemptId
        $duplicateParts = $duplicateState.Split('|')
        $duplicateConsumerCount = Get-WorkerSuccessCount -Attempt $attemptId
        if ($duplicateParts.Count -ge 6 -and
            $duplicateParts[0] -eq 'SENT' -and
            $duplicateParts[1] -eq 'SENT' -and
            $duplicateParts[2] -eq 'COMPLETED' -and
            [int]$duplicateParts[3] -eq 1 -and
            [int]$duplicateParts[4] -eq $testQuestionCount -and
            $duplicateParts[5] -eq 'SUBMITTED' -and
            $duplicateConsumerCount -ge 2) {
            break
        }
        Start-Sleep -Seconds 2
    }

    if ($duplicateConsumerCount -lt 2) {
        throw "Duplicate GRADE delivery was not confirmed in worker logs. State='$duplicateState'; consumer success count=$duplicateConsumerCount."
    }

    Add-ReportLine "Step 7/7: Duplicate GRADE message was consumed; exactly one completed grade row remains. State=$duplicateState"
    Add-ReportLine "WorkerGradeSuccessCountAfterDuplicate=$duplicateConsumerCount"
    Add-ReportLine 'RESULT=PASS'
    Add-ReportLine "TestExamId=$testExamId"
    Add-ReportLine "AttemptId=$attemptId"
    Add-ReportLine "FinishedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}
catch {
    Add-ReportLine "RESULT=FAIL: $($_.Exception.Message)"
    throw
}
finally {
    # Never leave the API running with the intentionally slowed test schedule.
    if ($restoreNeeded) {
        try {
            if (Test-Path -LiteralPath $overrideFile) {
                Remove-Item -LiteralPath $overrideFile -Force -ErrorAction SilentlyContinue
            }
            Add-ReportLine 'Cleanup: restoring API to the normal Compose configuration.'
            Invoke-Compose -Arguments @('-f', 'docker-compose.yml', 'up', '-d', '--no-deps', '--force-recreate', 'api')
            Wait-ApiHealthy -TimeoutSeconds 150
            Add-ReportLine 'Cleanup: API is healthy with the normal Outbox schedule.'
        }
        catch {
            Add-ReportLine "CLEANUP WARNING: Could not automatically restore API. Run: docker compose up -d --no-deps --force-recreate api. Details: $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $overrideFile) {
        Remove-Item -LiteralPath $overrideFile -Force -ErrorAction SilentlyContinue
    }
    if ($report.Count -gt 0) {
        New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
        [System.IO.File]::WriteAllLines($resultPath, [string[]]$report, ([System.Text.UTF8Encoding]::new($false)))
        Write-Host "Test log: $resultPath"
    }
    Pop-Location
}
