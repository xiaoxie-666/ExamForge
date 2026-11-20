[CmdletBinding()]
param(
    [int]$SourceExamId = 0,
    [ValidatePattern('^loadtest[0-9]{4}$')]
    [string]$Username = 'loadtest1002',
    [string]$Password = '',
    [string]$ApiBaseUrl = 'http://localhost:8080',
    [string]$DbName = '',
    [string]$DbUser = '',
    [string]$DbPassword = '',
    [ValidateRange(60, 600)]
    [int]$FailureDetectionTimeoutSeconds = 120,
    [ValidateRange(60, 900)]
    [int]$RecoveryTimeoutSeconds = 300
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
if ($SourceExamId -eq 0) {
    $idFile = Join-Path $projectRoot 'performance-test-exam-id.txt'
    if (-not (Test-Path -LiteralPath $idFile)) { $idFile = Join-Path $projectRoot 'ExamForge_JMeter_Performance/config/exam-id.txt' }
    if (-not (Test-Path -LiteralPath $idFile)) { throw 'SourceExamId was not supplied and no prepared performance-test exam ID was found.' }
    $idText = (Get-Content -LiteralPath $idFile -Raw).Trim()
    if ($idText -notmatch '^\d+$') { throw "Invalid SourceExamId file: $idFile" }
    $SourceExamId = [int]$idText
}
$ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$resultDirectory = Join-Path $projectRoot 'ExamForge_JMeter_Performance\results'
$resultPath = Join-Path $resultDirectory "broker-outage-recovery-$stamp.txt"
$overrideFile = Join-Path $projectRoot ("docker-compose.broker-outage-test-{0}.yml" -f $PID)
$report = New-Object 'System.Collections.Generic.List[string]'
$brokerStoppedByScript = $false
$overrideCreated = $false
$normalApiScheduleRestored = $false
$testExamId = 0
$attemptId = 0
$sourceQuestionCount = 0

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
    finally { $ErrorActionPreference = $previousPreference }
    if ($output) { foreach ($line in $output) { Write-Host $line } }
    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        throw "docker compose $($Arguments -join ' ') failed (exit=$exitCode). $details"
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
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        throw "MySQL query failed (exit=$exitCode). $details"
    }
    $clean = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne '' -and $_ -notmatch '^mysql:' })
    if ($clean.Count -eq 0) { return '' }
    return [string]$clean[-1]
}

function Test-ContainerRunning {
    param([string]$ContainerName)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $value = & docker inspect --format '{{.State.Running}}' $ContainerName 2>$null
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    return ($code -eq 0 -and ([string]$value).Trim() -eq 'true')
}

function Wait-ApiHealthy {
    param([int]$TimeoutSeconds = 150)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-RestMethod -Uri "$ApiBaseUrl/actuator/health" -TimeoutSec 5 -UseBasicParsing
            if ($health.status -eq 'UP') { return }
        }
        catch { Start-Sleep -Seconds 2 }
        Start-Sleep -Milliseconds 500
    }
    throw "API did not become healthy within $TimeoutSeconds seconds."
}

function Wait-BrokerPort {
    param([int]$TimeoutSeconds = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-ContainerRunning -ContainerName 'examforge-broker') {
            $reachable = Test-NetConnection -ComputerName '127.0.0.1' -Port 10911 `
                -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($reachable) { return }
        }
        Start-Sleep -Seconds 2
    }
    throw "RocketMQ Broker did not become reachable on localhost:10911 within $TimeoutSeconds seconds."
}

function Get-TestState {
    param([long]$Attempt)
    $sql = @"
SELECT CONCAT(
 COALESCE((SELECT CONCAT(status,':',retry_count) FROM outbox_event WHERE event_key='GRADE:$Attempt' LIMIT 1),'MISSING'), '|',
 COALESCE((SELECT CONCAT(status,':',retry_count) FROM outbox_event WHERE event_key='TIMEOUT:$Attempt' LIMIT 1),'MISSING'), '|',
 COALESCE((SELECT status FROM grade_result WHERE attempt_id=$Attempt LIMIT 1),'MISSING'), '|',
 (SELECT COUNT(*) FROM grade_result WHERE attempt_id=$Attempt), '|',
 (SELECT COUNT(*) FROM answer_record WHERE attempt_id=$Attempt), '|',
 COALESCE((SELECT status FROM exam_attempt WHERE id=$Attempt LIMIT 1),'MISSING')
);
"@
    $row = Invoke-MySql -Sql $sql
    if ([string]::IsNullOrWhiteSpace($row)) { throw "Could not read state for attempt $Attempt." }
    return $row
}

function Get-WorkerSuccessCount {
    param([long]$Attempt)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $logs = & docker compose logs --since=20m worker 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { return 0 }
    $allLogs = ($logs | ForEach-Object { $_.ToString() }) -join "`n"
    $pattern = 'Exam event consumed successfully: eventKey=GRADE:' + [regex]::Escape([string]$Attempt) + ','
    return [regex]::Matches($allLogs, $pattern).Count
}

function Wait-ForOutageFailure {
    param([long]$Attempt, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = ''
    while ((Get-Date) -lt $deadline) {
        $lastState = Get-TestState -Attempt $Attempt
        $parts = $lastState.Split('|')
        if ($parts.Count -ge 6) {
            $g = $parts[0].Split(':')
            $t = $parts[1].Split(':')
            if ($g.Count -eq 2 -and $t.Count -eq 2 -and
                $g[0] -eq 'PENDING' -and $t[0] -eq 'PENDING' -and
                [int]$g[1] -ge 1 -and [int]$t[1] -ge 1) {
                return $lastState
            }
            if (($g.Count -eq 2 -and $g[0] -eq 'FAILED') -or ($t.Count -eq 2 -and $t[0] -eq 'FAILED')) {
                throw "An Outbox event reached FAILED before Broker recovery. State=$lastState"
            }
        }
        Start-Sleep -Seconds 1
    }
    throw "Timed out waiting for both Outbox events to record a Broker-send failure. LastState=$lastState"
}

function Wait-ForRecoveredGrade {
    param([long]$Attempt, [int]$TimeoutSeconds, [int]$ExpectedAnswers)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = ''
    $lastConsumerCount = 0
    while ((Get-Date) -lt $deadline) {
        $lastState = Get-TestState -Attempt $Attempt
        $parts = $lastState.Split('|')
        $lastConsumerCount = Get-WorkerSuccessCount -Attempt $Attempt
        if ($parts.Count -ge 6) {
            $g = $parts[0].Split(':')
            $t = $parts[1].Split(':')
            if ($g.Count -eq 2 -and $t.Count -eq 2 -and
                $g[0] -eq 'SENT' -and $t[0] -eq 'SENT' -and
                $parts[2] -eq 'COMPLETED' -and [int]$parts[3] -eq 1 -and
                [int]$parts[4] -eq $ExpectedAnswers -and $parts[5] -eq 'SUBMITTED' -and
                $lastConsumerCount -ge 1) {
                return [pscustomobject]@{ State = $lastState; ConsumerSuccessCount = $lastConsumerCount }
            }
        }
        Start-Sleep -Seconds 2
    }
    throw "Timed out waiting for recovery. LastState='$lastState'; worker GRADE success count=$lastConsumerCount."
}

Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'docker-compose.yml'))) { throw 'docker-compose.yml not found.' }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker CLI not found.' }
    if ($SourceExamId -le 0) { throw 'SourceExamId must be a positive exam ID.' }
    if (-not (Test-ContainerRunning 'examforge-api') -or
        -not (Test-ContainerRunning 'examforge-worker') -or
        -not (Test-ContainerRunning 'examforge-broker') -or
        -not (Test-ContainerRunning 'examforge-namesrv') -or
        -not (Test-ContainerRunning 'examforge-mysql')) {
        throw 'Preflight failed: api, worker, broker, namesrv and mysql must all be running.'
    }
    Wait-ApiHealthy -TimeoutSeconds 30
    Wait-BrokerPort -TimeoutSeconds 30

    Add-ReportLine 'ExamForge RocketMQ Broker outage and Outbox recovery test'
    Add-ReportLine "StartedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-ReportLine "SourceExamId=$SourceExamId"
    Add-ReportLine "Username=$Username"
    Add-ReportLine 'Only a new isolated exam, one attempt, answer rows and their Outbox events will be added.'
    Add-ReportLine 'The existing exam 11 1000-user JMeter attempts/results will not be modified.'

    $accountCount = Invoke-MySql -Sql "SELECT COUNT(*) FROM sys_user WHERE username='$Username' AND role='STUDENT' AND status=1;"
    if ([int]$accountCount -ne 1) { throw "Student '$Username' is missing or disabled." }

    $sourceStats = Invoke-MySql -Sql @"
SELECT CONCAT(COUNT(*),'|',COALESCE(SUM(q.type='SUBJECTIVE'),0))
FROM exam_question eq JOIN question_bank q ON q.id=eq.question_id
WHERE eq.exam_id=$SourceExamId;
"@
    $sourceParts = $sourceStats.Split('|')
    if ($sourceParts.Count -ne 2 -or [int]$sourceParts[0] -lt 1 -or [int]$sourceParts[1] -ne 0) {
        throw "Source exam must have questions and be objective-only. Found: $sourceStats"
    }
    $sourceQuestionCount = [int]$sourceParts[0]
    Add-ReportLine "SourceExamQuestions=$sourceQuestionCount; SubjectiveQuestions=0"

    # Pause the API Outbox scheduler while a fresh attempt is created. This prevents
    # the test event from being published before the Broker is deliberately stopped.
    $overrideContent = @'
services:
  api:
    environment:
      JAVA_TOOL_OPTIONS: "-Duser.timezone=Asia/Shanghai -Dexamforge.outbox.publish-interval-ms=600000"
'@
    [System.IO.File]::WriteAllText($overrideFile, $overrideContent, ([System.Text.UTF8Encoding]::new($false)))
    $overrideCreated = $true
    Add-ReportLine 'Step 1/7: Temporarily paused Outbox polling by setting a 10-minute interval.'
    Invoke-Compose -Arguments @('-f','docker-compose.yml','-f',$overrideFile,'up','-d','--no-deps','--force-recreate','api')
    Wait-ApiHealthy -TimeoutSeconds 150
    Start-Sleep -Seconds 8

    $testTitle = "BrokerOutage-$stamp-$PID"
    $createSql = @"
SET @source_exam_id=$SourceExamId;
SET @test_title='$testTitle';
INSERT INTO exam(title,description,status,start_time,end_time,duration_minutes,created_by,create_time,update_time)
SELECT @test_title, CONCAT('Isolated Broker outage test cloned from exam ',id), 'PUBLISHED',
       DATE_SUB(NOW(),INTERVAL 5 MINUTE), DATE_ADD(NOW(),INTERVAL 1 DAY), 60,
       created_by,NOW(),NOW() FROM exam WHERE id=@source_exam_id;
SET @new_exam_id=LAST_INSERT_ID();
INSERT INTO exam_question(exam_id,question_id,sort_order,score)
SELECT @new_exam_id,question_id,sort_order,score FROM exam_question WHERE exam_id=@source_exam_id;
SELECT CONCAT(@new_exam_id,'|',(SELECT COUNT(*) FROM exam_question WHERE exam_id=@new_exam_id));
"@
    $createLine = Invoke-MySql -Sql $createSql
    if ($createLine -notmatch '^\d+\|\d+$') { throw "Could not create isolated exam: $createLine" }
    $createParts = $createLine.Split('|')
    $testExamId = [int]$createParts[0]
    if ($testExamId -le 0 -or [int]$createParts[1] -ne $sourceQuestionCount) { throw 'Isolated exam question copy was incomplete.' }
    Add-ReportLine "Step 2/7: Created isolated objective-only exam $testExamId with $sourceQuestionCount questions."

    $loginBody = @{ username=$Username; password=$Password } | ConvertTo-Json -Compress
    $login = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/api/auth/login" -ContentType 'application/json' -Body $loginBody -TimeoutSec 20 -UseBasicParsing
    if ($login.code -ne 0 -or -not $login.data.token) { throw "Login failed: $($login | ConvertTo-Json -Depth 6 -Compress)" }
    $headers = @{ Authorization = "Bearer $($login.data.token)" }
    $started = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/api/candidate/exams/$testExamId/start" -Headers $headers -TimeoutSec 30 -UseBasicParsing
    if ($started.code -ne 0 -or -not $started.data.attemptId) { throw "Start exam failed: $($started | ConvertTo-Json -Depth 6 -Compress)" }
    $attemptId = [long]$started.data.attemptId
    $submitted = Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/api/candidate/attempts/$attemptId/submit" -Headers $headers -TimeoutSec 30 -UseBasicParsing
    if ($submitted.code -ne 0) { throw "Submit attempt $attemptId failed: $($submitted | ConvertTo-Json -Depth 6 -Compress)" }
    Add-ReportLine "Step 3/7: Created and submitted isolated attempt $attemptId through the real API."

    Start-Sleep -Seconds 2
    $pendingState = Get-TestState -Attempt $attemptId
    $pendingParts = $pendingState.Split('|')
    if ($pendingParts.Count -lt 6 -or $pendingParts[0] -ne 'PENDING:0' -or $pendingParts[1] -ne 'PENDING:0') {
        throw "Expected both new Outbox rows to remain PENDING:0 before Broker outage. Actual=$pendingState"
    }
    Add-ReportLine "Step 4/7: Confirmed new GRADE/TIMEOUT Outbox rows are pending before outage: $pendingState"

    Add-ReportLine 'Step 5/7: Stopping RocketMQ Broker only; NameServer, API, Worker, MySQL and Redis remain running.'
    Invoke-Compose -Arguments @('stop','broker')
    $brokerStoppedByScript = $true
    if (Test-ContainerRunning 'examforge-broker') { throw 'Broker container still reports running after stop.' }

    # Remove the slow-poll override and recreate API without dependency startup.
    # The Broker remains stopped, so the next Outbox scan must record send failures.
    Remove-Item -LiteralPath $overrideFile -Force
    $overrideCreated = $false
    Add-ReportLine 'Step 6/7: Restoring the normal 1-second Outbox schedule while Broker is unavailable.'
    Invoke-Compose -Arguments @('-f','docker-compose.yml','up','-d','--no-deps','--force-recreate','api')
    $normalApiScheduleRestored = $true
    Wait-ApiHealthy -TimeoutSeconds 150

    $failureState = Wait-ForOutageFailure -Attempt $attemptId -TimeoutSeconds $FailureDetectionTimeoutSeconds
    Add-ReportLine "BrokerUnavailableState=$failureState"
    Add-ReportLine 'Confirmed: both GRADE and TIMEOUT Outbox events recorded at least one failed send and remain retryable.'

    Add-ReportLine 'Step 7/7: Restarting Broker and waiting for Outbox retry, Worker consumption and final grade persistence.'
    Invoke-Compose -Arguments @('start','broker')
    $brokerStoppedByScript = $false
    Wait-BrokerPort -TimeoutSeconds 120
    Add-ReportLine 'Broker container and host port 10911 are reachable again.'

    $recovered = Wait-ForRecoveredGrade -Attempt $attemptId -TimeoutSeconds $RecoveryTimeoutSeconds -ExpectedAnswers $sourceQuestionCount
    Add-ReportLine "RecoveredState=$($recovered.State)"
    Add-ReportLine "WorkerGradeSuccessCount=$($recovered.ConsumerSuccessCount)"
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
    # Always restore Broker before restoring the normal API publisher schedule.
    if ($brokerStoppedByScript) {
        try {
            Add-ReportLine 'Cleanup: restarting RocketMQ Broker.'
            Invoke-Compose -Arguments @('start','broker')
            Wait-BrokerPort -TimeoutSeconds 120
            $brokerStoppedByScript = $false
            Add-ReportLine 'Cleanup: Broker is reachable.'
        }
        catch { Add-ReportLine "CLEANUP WARNING: Broker restart failed. Run: docker compose start broker. Details: $($_.Exception.Message)" }
    }

    if ($overrideCreated -or -not $normalApiScheduleRestored) {
        try {
            if (Test-Path -LiteralPath $overrideFile) { Remove-Item -LiteralPath $overrideFile -Force -ErrorAction SilentlyContinue }
            Add-ReportLine 'Cleanup: restoring API to the normal Compose configuration.'
            Invoke-Compose -Arguments @('-f','docker-compose.yml','up','-d','--no-deps','--force-recreate','api')
            Wait-ApiHealthy -TimeoutSeconds 150
            Add-ReportLine 'Cleanup: API is healthy with the normal Outbox schedule.'
        }
        catch { Add-ReportLine "CLEANUP WARNING: API restore failed. Run: docker compose up -d --no-deps --force-recreate api. Details: $($_.Exception.Message)" }
    }

    if (Test-Path -LiteralPath $overrideFile) { Remove-Item -LiteralPath $overrideFile -Force -ErrorAction SilentlyContinue }
    if ($report.Count -gt 0) {
        New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
        [System.IO.File]::WriteAllLines($resultPath, [string[]]$report, ([System.Text.UTF8Encoding]::new($false)))
        Write-Host "Test log: $resultPath"
    }
    Pop-Location
}
