[CmdletBinding()]
param(
    [string]$DbName = '',
    [string]$DbUser = '',
    [string]$DbPassword = '',
    [ValidateRange(90, 600)]
    [int]$DlqTimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'scripts/Import-ExamForgeEnv.ps1') -ProjectRoot $projectRoot
if ([string]::IsNullOrWhiteSpace($DbName)) { $DbName = if ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { 'examforge' } }
if ([string]::IsNullOrWhiteSpace($DbUser)) { $DbUser = if ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'examforge' } }
if ([string]::IsNullOrWhiteSpace($DbPassword)) { $DbPassword = $env:MYSQL_PASSWORD }
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw 'MYSQL_PASSWORD is required in .env.' }
$sourceFile = Join-Path $projectRoot 'backend/src/main/java/com/examforge/mq/ExamEventConsumer.java'
$resultsDir = Join-Path $projectRoot 'ExamForge_JMeter_Performance/results'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$eventKey = "DLQ-TEST-$stamp-$PID"
$testGroup = "examforge-dlq-test-$stamp-$PID"
$testTopic = "examforge-dlq-test-$stamp-$PID"
$dlqTopic = "%DLQ%$testGroup"
$testContainer = "examforge-worker-dlq-$PID"
$testApiContainer = "examforge-api-dlq-$PID"
$backupFile = Join-Path $resultsDir "ExamEventConsumer.original-$stamp.java"
$reportPath = Join-Path $resultsDir "dlq-test-$stamp.txt"
$report = New-Object 'System.Collections.Generic.List[string]'

$script:sourceBackedUp = $false
$script:servicesStopped = $false
$script:restoreSucceeded = $true
$script:testFailure = $null

New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

function Add-ReportLine {
    param([string]$Line)
    $script:report.Add($Line)
    Write-Host $Line
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & docker @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $textOutput = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "docker $($Arguments -join ' ') failed (exit=$exitCode).`n$textOutput"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $textOutput
    }
}

function Invoke-MySql {
    param([Parameter(Mandatory = $true)][string]$Sql)

    $result = Invoke-Docker -Arguments @(
        'compose','exec','-T','-e',"MYSQL_PWD=$DbPassword",'mysql','mysql',
        '--batch','--raw','--skip-column-names',"-u$DbUser",$DbName,'-e',$Sql
    )

    $lines = @($result.Output -split "`r?`n" | Where-Object {
        $_.Trim() -ne '' -and $_ -notmatch '^mysql:'
    })
    if ($lines.Count -eq 0) { return '' }
    return [string]$lines[-1].Trim()
}

function Invoke-MqAdmin {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    return Invoke-Docker -Arguments (@('compose','exec','-T','broker','sh','mqadmin') + $Arguments) -AllowFailure:$AllowFailure
}

function Test-ContainerRunning {
    param([Parameter(Mandatory = $true)][string]$ContainerName)

    $result = Invoke-Docker -Arguments @('inspect','--format','{{.State.Running}}',$ContainerName) -AllowFailure
    return ($result.ExitCode -eq 0 -and $result.Output.Trim() -eq 'true')
}

function Test-MessageIdRow {
    param([AllowEmptyString()][string]$Text)

    # mqadmin queryMsgByKey prints rows like:
    # AC14000500012F92E0F45FEA9B230002  3  1484
    # Do not treat a Java exception/stack trace as a successful query.
    return [regex]::IsMatch($Text, '(?im)^\s*[0-9a-f]{32}\s+\d+\s+\d+\s*$')
}

function Wait-TestWorkerReady {
    param([int]$TimeoutSeconds = 90)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastLogs = ''
    while ((Get-Date) -lt $deadline) {
        if (Test-ContainerRunning $testContainer) {
            $logs = Invoke-Docker -Arguments @('logs','--since','5m',$testContainer) -AllowFailure
            $lastLogs = $logs.Output
            if ($lastLogs -match [regex]::Escape("consumerGroup='$testGroup'") -and
                $lastLogs -match 'running container:') {
                return
            }
            if ($lastLogs -match 'APPLICATION FAILED TO START|Application run failed') {
                throw "Temporary DLQ Worker failed during startup.`n$lastLogs"
            }
        }
        Start-Sleep -Seconds 2
    }

    $lastLogs = (Invoke-Docker -Arguments @('logs','--since','10m',$testContainer) -AllowFailure).Output
    throw "Temporary DLQ consumer did not become ready within $TimeoutSeconds seconds.`n$lastLogs"
}

function Wait-TestApiReady {
    param([int]$TimeoutSeconds = 90)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastLogs = ''
    $expectedJvmProperty = "-Dexamforge.rocketmq.topic=$testTopic"

    while ((Get-Date) -lt $deadline) {
        if (Test-ContainerRunning $testApiContainer) {
            $logs = Invoke-Docker -Arguments @('logs','--since','5m',$testApiContainer) -AllowFailure
            $lastLogs = $logs.Output

            if ($lastLogs -match 'APPLICATION FAILED TO START|Application run failed') {
                throw "Temporary API publisher failed during startup.`n$lastLogs"
            }

            # Java prints JAVA_TOOL_OPTIONS on startup. Require the isolated topic
            # override to be visible before inserting the poison event.
            if ($lastLogs -match 'Picked up JAVA_TOOL_OPTIONS' -and
                $lastLogs -match [regex]::Escape($expectedJvmProperty) -and
                $lastLogs -match 'Started ') {
                return
            }
        }
        Start-Sleep -Seconds 2
    }

    $lastLogs = (Invoke-Docker -Arguments @('logs','--since','10m',$testApiContainer) -AllowFailure).Output
    throw "Temporary API did not become ready with the isolated RocketMQ topic override.`nExpected JVM property: $expectedJvmProperty`nLogs:`n$lastLogs"
}

function Wait-OutboxPublished {
    param([int]$TimeoutSeconds = 120)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastState = ''
    while ((Get-Date) -lt $deadline) {
        $lastState = Invoke-MySql -Sql "SELECT CONCAT(status,'|',retry_count) FROM outbox_event WHERE event_key='$eventKey' LIMIT 1;"
        if ($lastState -match '^SENT\|') { return $lastState }
        if ($lastState -match '^FAILED\|') {
            throw "Test Outbox event entered FAILED state: $lastState"
        }
        Start-Sleep -Seconds 2
    }

    $apiLogs = (Invoke-Docker -Arguments @('logs','--since','10m',$testApiContainer) -AllowFailure).Output
    throw "Timed out waiting for the isolated API OutboxPublisher. LastState=$lastState`nTemporary API logs:`n$apiLogs"
}

function Wait-DlqMessage {
    param([int]$TimeoutSeconds)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastTopicList = ''
    $lastQuery = ''
    $lastTopicStatus = ''

    while ((Get-Date) -lt $deadline) {
        $topicList = Invoke-MqAdmin -Arguments @('topicList','-n','namesrv:9876') -AllowFailure
        $lastTopicList = $topicList.Output
        $topics = @($lastTopicList -split "`r?`n" | ForEach-Object { $_.Trim() })

        # The DLQ topic must actually be registered. A retry topic alone is not a DLQ.
        if ($topicList.ExitCode -eq 0 -and $topics -contains $dlqTopic) {
            $query = Invoke-MqAdmin -Arguments @(
                'queryMsgByKey','-n','namesrv:9876','-t',$dlqTopic,'-k',$eventKey
            ) -AllowFailure
            $lastQuery = $query.Output

            if ($query.ExitCode -eq 0 -and (Test-MessageIdRow -Text $lastQuery)) {
                $status = Invoke-MqAdmin -Arguments @(
                    'topicStatus','-n','namesrv:9876','-t',$dlqTopic
                ) -AllowFailure
                $lastTopicStatus = $status.Output

                return [pscustomobject]@{
                    Query = $lastQuery
                    TopicStatus = $lastTopicStatus
                    TopicList = $lastTopicList
                }
            }
        }

        Start-Sleep -Seconds 5
    }

    $workerLogs = (Invoke-Docker -Arguments @('logs','--since','15m',$testContainer) -AllowFailure).Output
    throw @"
DLQ verification timed out after $TimeoutSeconds seconds.
The script did not find a valid Message ID row for the unique key in the actual DLQ topic.
Last topicList output:
$lastTopicList
Last DLQ query output:
$lastQuery
Last DLQ topicStatus output:
$lastTopicStatus
Temporary Worker logs:
$workerLogs
"@
}

function Wait-OriginalServices {
    param([int]$TimeoutSeconds = 120)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $apiRunning = Test-ContainerRunning 'examforge-api'
        $workerRunning = Test-ContainerRunning 'examforge-worker'

        if ($apiRunning -and $workerRunning) {
            try {
                $health = Invoke-RestMethod -Uri 'http://localhost:8080/actuator/health' -TimeoutSec 5 -UseBasicParsing
                if ($health.status -eq 'UP') { return }
            }
            catch {
                # API may still be starting. Continue polling.
            }
        }
        Start-Sleep -Seconds 3
    }

    $apiLogs = (Invoke-Docker -Arguments @('logs','--tail','80','examforge-api') -AllowFailure).Output
    $workerLogs = (Invoke-Docker -Arguments @('logs','--tail','80','examforge-worker') -AllowFailure).Output
    throw "Original API/Worker did not recover within $TimeoutSeconds seconds.`nAPI logs:`n$apiLogs`nWorker logs:`n$workerLogs"
}

function Restore-OriginalServices {
    Add-ReportLine 'Cleanup: stopping isolated test containers and restoring the original API/Worker configuration.'

    Invoke-Docker -Arguments @('stop',$testApiContainer) -AllowFailure | Out-Null
    Invoke-Docker -Arguments @('rm','-f',$testApiContainer) -AllowFailure | Out-Null
    Invoke-Docker -Arguments @('stop',$testContainer) -AllowFailure | Out-Null
    Invoke-Docker -Arguments @('rm','-f',$testContainer) -AllowFailure | Out-Null

    if (-not $script:sourceBackedUp -and -not $script:servicesStopped) {
        Add-ReportLine 'No API/Worker state was changed; no service rebuild or restart is necessary.'
        return
    }

    if ($script:sourceBackedUp) {
        if (-not (Test-Path -LiteralPath $backupFile)) {
            $script:restoreSucceeded = $false
            Add-ReportLine "RESTORE ERROR: source backup is missing: $backupFile. API/Worker will remain stopped to avoid starting a patched image."
            return
        }
        Copy-Item -LiteralPath $backupFile -Destination $sourceFile -Force
        Add-ReportLine 'Original ExamEventConsumer.java restored from its byte-for-byte backup.'

        # API and Worker share examforge-backend:local. Rebuild the shared image
        # after restoring Java source, then recreate both services from that image.
        $build = Invoke-Docker -Arguments @('compose','build','worker') -AllowFailure
        if ($build.ExitCode -ne 0) {
            $script:restoreSucceeded = $false
            Add-ReportLine "RESTORE ERROR: original backend image rebuild failed. API/Worker remain stopped.`n$($build.Output)"
            return
        }

        $up = Invoke-Docker -Arguments @(
            'compose','up','-d','--no-deps','--force-recreate','api','worker'
        ) -AllowFailure
        if ($up.ExitCode -ne 0) {
            $script:restoreSucceeded = $false
            Add-ReportLine "RESTORE ERROR: could not recreate original API/Worker.`n$($up.Output)"
            return
        }

        try { Remove-Item -LiteralPath $backupFile -Force } catch { }
    }
    elseif ($script:servicesStopped) {
        $up = Invoke-Docker -Arguments @('compose','up','-d','--no-deps','api','worker') -AllowFailure
        if ($up.ExitCode -ne 0) {
            $script:restoreSucceeded = $false
            Add-ReportLine "RESTORE ERROR: could not restart original API/Worker.`n$($up.Output)"
            return
        }
    }

    try {
        Wait-OriginalServices -TimeoutSeconds 120
        Add-ReportLine 'Original API health is UP and the normal Worker is running.'
    }
    catch {
        $script:restoreSucceeded = $false
        Add-ReportLine "RESTORE ERROR: $($_.Exception.Message)"
    }
}

Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'docker-compose.yml'))) {
        throw 'docker-compose.yml not found. Run this script from the ExamForge project structure.'
    }
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "ExamEventConsumer.java not found: $sourceFile"
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI not found.'
    }

    foreach ($container in @(
        'examforge-api','examforge-worker','examforge-broker',
        'examforge-namesrv','examforge-mysql','examforge-redis','examforge-xxl-admin'
    )) {
        if (-not (Test-ContainerRunning $container)) {
            throw "Preflight failed: container '$container' must be running. Start the ExamForge stack first."
        }
    }

    if (Test-ContainerRunning $testContainer) {
        throw "A container named '$testContainer' already exists. Inspect/remove it before running this test."
    }
    if (Test-ContainerRunning $testApiContainer) {
        throw "A container named '$testApiContainer' already exists. Inspect/remove it before running this test."
    }

    $health = Invoke-RestMethod -Uri 'http://localhost:8080/actuator/health' -TimeoutSec 8 -UseBasicParsing
    if ($health.status -ne 'UP') { throw "API is not healthy: $($health.status)" }

    $originalText = [System.IO.File]::ReadAllText($sourceFile)
    if (-not $originalText.Contains('maxReconsumeTimes = 16')) {
        throw 'Expected maxReconsumeTimes = 16 was not found exactly. No source changes were made.'
    }

    Add-ReportLine 'ExamForge RocketMQ Dead-Letter Queue (DLQ) verification'
    Add-ReportLine "StartedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-ReportLine "TestTopic=$testTopic"
    Add-ReportLine "TestConsumerGroup=$testGroup"
    Add-ReportLine "DlqTopic=$dlqTopic"
    Add-ReportLine "EventKey=$eventKey"
    Add-ReportLine 'Isolation: the test uses a dedicated Topic and consumer group. The production examforge-events Topic is not used.'
    Add-ReportLine 'The test adds one isolated Outbox row only; it does not modify exams, attempts, answers, grades, or the previous JMeter data.'
    Add-ReportLine 'NOTICE: the normal API and Worker are stopped briefly while the isolated test API/Worker run. The Web container remains running, but API requests may be unavailable during this interval.'

    # The temporary API publisher scans every PENDING Outbox row. Refuse to run
    # if unrelated pending events exist, so none can be redirected to the test Topic.
    $pendingBefore = [int](Invoke-MySql -Sql "SELECT COUNT(*) FROM outbox_event WHERE status IN ('PENDING','SENDING');")
    if ($pendingBefore -ne 0) {
        throw "Preflight refused: found $pendingBefore existing PENDING/SENDING Outbox rows. Resolve them before running DLQ isolation test."
    }

    Add-ReportLine 'Step 1/8: Stopping the normal API and Worker to isolate the Outbox publisher and production consumer.'
    $script:servicesStopped = $true
    Invoke-Docker -Arguments @('compose','stop','api','worker') | Out-Null

    $pendingAfterStop = [int](Invoke-MySql -Sql "SELECT COUNT(*) FROM outbox_event WHERE status IN ('PENDING','SENDING');")
    if ($pendingAfterStop -ne 0) {
        throw "Preflight refused after stopping services: found $pendingAfterStop PENDING/SENDING Outbox rows. No test event was inserted."
    }

    Add-ReportLine 'Step 2/8: Backing up ExamEventConsumer.java and temporarily setting maxReconsumeTimes=1.'
    Copy-Item -LiteralPath $sourceFile -Destination $backupFile -Force
    $script:sourceBackedUp = $true
    $patchedText = $originalText.Replace('maxReconsumeTimes = 16','maxReconsumeTimes = 1')
    [System.IO.File]::WriteAllText($sourceFile,$patchedText,[System.Text.UTF8Encoding]::new($false))

    Add-ReportLine 'Step 3/8: Building the temporary Worker image.'
    $build = Invoke-Docker -Arguments @('compose','build','worker')
    Add-ReportLine 'Temporary Worker image built.'

    Add-ReportLine 'Step 4/8: Creating and checking the isolated RocketMQ Topic.'
    $createTopic = Invoke-MqAdmin -Arguments @(
        'updateTopic','-n','namesrv:9876','-b','127.0.0.1:10911',
        '-t',$testTopic,'-r','8','-w','8'
    ) -AllowFailure
    if ($createTopic.ExitCode -ne 0 -or $createTopic.Output -match '(?i)exception|failed|error') {
        throw "Could not create isolated RocketMQ Topic '$testTopic'.`n$($createTopic.Output)"
    }

    $route = Invoke-MqAdmin -Arguments @('topicRoute','-n','namesrv:9876','-t',$testTopic) -AllowFailure
    if ($route.ExitCode -ne 0 -or $route.Output -match '(?i)no topic route|exception|failed') {
        throw "Isolated Topic has no valid route: $testTopic`n$($route.Output)"
    }
    Add-ReportLine "IsolatedTopicRoute=PASS; Topic=$testTopic"

    Add-ReportLine 'Step 5/8: Starting the temporary Worker with the isolated Topic and consumer group.'
    $javaOptions = "-Duser.timezone=Asia/Shanghai -Dexamforge.rocketmq.topic=$testTopic -Dexamforge.rocketmq.consumer-group=$testGroup"
    Invoke-Docker -Arguments @(
        'compose','run','-d','--no-deps','--name',$testContainer,
        '-e',"JAVA_TOOL_OPTIONS=$javaOptions",'worker'
    ) | Out-Null
    Wait-TestWorkerReady -TimeoutSeconds 90
    Add-ReportLine 'Temporary Worker is subscribed to the isolated Topic.'

    Add-ReportLine 'Step 6/8: Starting a temporary API publisher whose Outbox topic is overridden to the isolated Topic.'
    $apiJavaOptions = "-Duser.timezone=Asia/Shanghai -Dexamforge.rocketmq.topic=$testTopic"
    Invoke-Docker -Arguments @(
        'compose','run','-d','--no-deps','--name',$testApiContainer,
        '-e',"JAVA_TOOL_OPTIONS=$apiJavaOptions",'api'
    ) | Out-Null

    Wait-TestApiReady -TimeoutSeconds 90
    Add-ReportLine "Temporary API startup confirmed; JVM topic override is $testTopic."

    $sql = @"
INSERT INTO outbox_event
(event_key,event_type,payload,status,retry_count,deliver_at,next_retry_at,create_time,update_time)
VALUES
('$eventKey','GRADE',JSON_OBJECT('type','INVALID_TEST','attemptId',1,'eventKey','$eventKey'),
 'PENDING',0,NULL,NOW(),NOW(),NOW());
SELECT CONCAT(id,'|',status) FROM outbox_event WHERE event_key='$eventKey' LIMIT 1;
"@
    $insertState = Invoke-MySql -Sql $sql
    if ($insertState -notmatch '^\d+\|PENDING$') {
        throw "Could not create the isolated Outbox test event. Result=$insertState"
    }
    Add-ReportLine "OutboxEvent=$insertState"

    $publishedState = Wait-OutboxPublished -TimeoutSeconds 120
    Add-ReportLine "PublisherState=$publishedState; the message was sent to $testTopic."

    # Stop the temporary API publisher immediately after its one event is SENT.
    Invoke-Docker -Arguments @('stop',$testApiContainer) | Out-Null
    Add-ReportLine 'Temporary API publisher stopped after publishing the single isolated event.'

    Add-ReportLine "Step 7/8: Waiting up to $DlqTimeoutSeconds seconds for retry exhaustion and a verifiable DLQ message."
    $dlqResult = Wait-DlqMessage -TimeoutSeconds $DlqTimeoutSeconds
    Add-ReportLine 'DLQ verification passed: the actual %DLQ% topic exists and queryMsgByKey returned a valid Message ID row.'
    Add-ReportLine '--- DLQ topicList match ---'
    Add-ReportLine $dlqTopic
    Add-ReportLine '--- mqadmin queryMsgByKey output ---'
    foreach ($line in ($dlqResult.Query -split "`r?`n")) {
        if ($line.Trim()) { Add-ReportLine $line }
    }
    Add-ReportLine '--- mqadmin topicStatus output ---'
    foreach ($line in ($dlqResult.TopicStatus -split "`r?`n")) {
        if ($line.Trim()) { Add-ReportLine $line }
    }

    $workerLogs = (Invoke-Docker -Arguments @('logs','--since','15m',$testContainer) -AllowFailure).Output
    $failurePattern = 'Exam event consumption failed: eventKey=' + [regex]::Escape($eventKey)
    $failureCount = [regex]::Matches($workerLogs,$failurePattern).Count
    Add-ReportLine "ConsumerFailureLogCount=$failureCount"
    if ($failureCount -lt 1) {
        throw 'The DLQ message was found, but the isolated Worker failure log for the unique event key was not found.'
    }
    if ($failureCount -lt 2) {
        Add-ReportLine 'WARNING: fewer than two application failure log entries were captured; the Broker-side DLQ message is the primary retry-exhaustion evidence.'
    }

    $productionQuery = Invoke-MqAdmin -Arguments @(
        'queryMsgByKey','-n','namesrv:9876','-t','examforge-events','-k',$eventKey
    ) -AllowFailure
    if (Test-MessageIdRow -Text $productionQuery.Output) {
        throw "Isolation check failed: the test EventKey was also found on production Topic examforge-events.`n$($productionQuery.Output)"
    }
    Add-ReportLine 'ProductionTopicIsolation=PASS; the unique test EventKey was not found on examforge-events.'

    Add-ReportLine 'Step 8/8: DLQ retry-exhaustion and production-topic isolation checks completed.'
    Add-ReportLine 'RESULT=PASS'
}
catch {
    $script:testFailure = $_.Exception
    Add-ReportLine 'RESULT=FAIL'
    Add-ReportLine "ERROR=$($_.Exception.Message)"
}
finally {
    try {
        Restore-OriginalServices
        if ($script:restoreSucceeded) {
            Add-ReportLine 'RESTORE_STATUS=PASS'
        }
        else {
            Add-ReportLine 'RESTORE_STATUS=FAILED - inspect this log; do not run more tests until the original API/Worker are restored.'
        }
    }
    catch {
        $script:restoreSucceeded = $false
        Add-ReportLine "RESTORE_STATUS=FAILED - $($_.Exception.Message)"
    }

    Add-ReportLine "FinishedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $report | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Test log: $reportPath"
    Pop-Location
}

if (-not $script:restoreSucceeded) {
    throw "DLQ test cleanup did not restore the original API/Worker. Inspect $reportPath and restore the original Worker before continuing."
}
if ($script:testFailure) {
    throw "DLQ test failed. Original API/Worker were restored. See $reportPath. Error: $($script:testFailure.Message)"
}

Write-Host "`nDLQ TEST PASSED. Original API health and Worker startup were restored."
Write-Host "Isolated test Topic: $testTopic"
Write-Host "Isolated DLQ Topic: $dlqTopic"
Write-Host "Isolated consumer group: $testGroup"
