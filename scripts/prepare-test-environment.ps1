[CmdletBinding()]
param(
    [switch]$ConfirmReset
)

$ErrorActionPreference = 'Stop'

if (-not $ConfirmReset) {
    throw "This operation deletes historical exams, attempts, answers, grades, Outbox rows, and all users except admin/teacher/student. A MySQL backup is created first. Re-run with -ConfirmReset only when you intend to reset the test environment."
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot 'scripts/Import-ExamForgeEnv.ps1') -ProjectRoot $ProjectRoot
$ResetSqlPath = Join-Path $ProjectRoot 'database/reset-test-data.sql'
$PrepareSqlPath = Join-Path $ProjectRoot 'database/prepare-test-data.sql'

if (-not (Test-Path (Join-Path $ProjectRoot 'docker-compose.yml'))) {
    throw "docker-compose.yml was not found under $ProjectRoot"
}
if (-not (Test-Path $ResetSqlPath)) {
    throw "Required SQL file was not found: $ResetSqlPath"
}
if (-not (Test-Path $PrepareSqlPath)) {
    throw "Required SQL file was not found: $PrepareSqlPath"
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker command was not found. Start Docker Desktop first."
}
if ([string]::IsNullOrWhiteSpace($env:ComSpec)) {
    throw "ComSpec is unavailable. Run this script from Windows PowerShell."
}

# Keep credentials out of mysql/mysqldump command-line arguments.
# docker compose exec passes MYSQL_PWD into the temporary container process.
$DbName = if ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { 'examforge' }
$DbUser = if ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'examforge' }
$DbPassword = $env:MYSQL_PASSWORD
$LoadTestPassword = $env:LOADTEST_USER_PASSWORD
if ([string]::IsNullOrWhiteSpace($LoadTestPassword)) { throw 'LOADTEST_USER_PASSWORD is required in .env.' }
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw 'MYSQL_PASSWORD is required in .env.' }
$OriginalLoadtestUsersEnabled = $env:LOADTEST_USERS_ENABLED

$DatabaseResetStarted = $false
$backupPath = $null

Push-Location $ProjectRoot
try {
    Write-Host "ExamForge test-environment preparation (Windows PowerShell native-command safe)" -ForegroundColor Cyan
    Write-Host "Project: $ProjectRoot"

    # Windows PowerShell 5.1 can promote native stderr output (Docker Compose
    # progress messages such as "Container ... Stopping/Running") to a
    # NativeCommandError. With $ErrorActionPreference='Stop', that can abort a
    # successful docker command. Run native tools in this helper with a local
    # Continue preference, then trust the process exit code for success/failure.
    function Invoke-NativeCapture {
        param(
            [Parameter(Mandatory = $true)]
            [string]$FilePath,

            [Parameter()]
            [AllowEmptyCollection()]
            [string[]]$Arguments = @()
        )

        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $capturedOutput = @(& $FilePath @Arguments 2>&1)
            $nativeExitCode = $LASTEXITCODE

            if ($null -eq $nativeExitCode) {
                $nativeExitCode = 0
            }

            return [pscustomobject]@{
                ExitCode = [int]$nativeExitCode
                Output   = @($capturedOutput)
            }
        }
        finally {
            $ErrorActionPreference = $savedPreference
        }
    }

    function Invoke-DockerChecked {
        param(
            [Parameter(Mandatory = $true)]
            [string[]]$Arguments,

            [Parameter(Mandatory = $true)]
            [string]$FailureMessage
        )

        $nativeResult = Invoke-NativeCapture -FilePath 'docker' -Arguments $Arguments
        $output = @($nativeResult.Output)
        $exitCode = $nativeResult.ExitCode

        foreach ($line in $output) {
            Write-Host $line
        }

        if ($exitCode -ne 0) {
            $detail = ($output | Out-String).Trim()
            throw "$FailureMessage (exit code $exitCode). $detail"
        }
    }

    function Invoke-DbScalar {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Query
        )

        $dockerArgs = @(
            'compose', 'exec', '-T',
            '-e', "MYSQL_PWD=$DbPassword",
            'mysql', 'mysql',
            '--default-character-set=utf8mb4',
            '--batch',
            '--skip-column-names',
            '-u', $DbUser,
            $DbName,
            '-e', $Query
        )

        # Redirect native stderr to avoid Windows PowerShell treating harmless
        # Docker/MySQL diagnostics as terminating NativeCommandError records.
        $nativeResult = Invoke-NativeCapture -FilePath 'docker' -Arguments $dockerArgs
        $output = @($nativeResult.Output)
        $exitCode = $nativeResult.ExitCode

        if ($exitCode -ne 0) {
            $detail = ($output | Out-String).Trim()
            throw "MySQL query failed (exit code $exitCode): $Query`n$detail"
        }

        $lines = @(
            $output |
                ForEach-Object { "$_".Trim() } |
                Where-Object {
                    $_ -ne '' -and $_ -notmatch '^mysql: \[Warning\]'
                }
        )

        if ($lines.Count -eq 0) {
            throw "MySQL query returned no scalar value: $Query"
        }

        return [string]$lines[-1]
    }

    function Invoke-SqlFile {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        $fullPath = (Resolve-Path -LiteralPath $Path).Path

        # cmd.exe redirection preserves the SQL file's UTF-8 bytes when piping
        # the file into mysql on Windows PowerShell 5.1.
        $safeDbPassword = $DbPassword.Replace('"', '""')
        $command = 'docker compose exec -T -e "MYSQL_PWD=' + $safeDbPassword + '"' +
            ' mysql mysql --default-character-set=utf8mb4 -u' + $DbUser +
            ' ' + $DbName + ' < "' + $fullPath + '"'

        $nativeResult = Invoke-NativeCapture -FilePath $env:ComSpec -Arguments @('/d', '/s', '/c', $command)
        $output = @($nativeResult.Output)
        $exitCode = $nativeResult.ExitCode

        foreach ($line in $output) {
            Write-Host $line
        }

        if ($exitCode -ne 0) {
            $detail = ($output | Out-String).Trim()
            throw "SQL execution failed (exit code $exitCode): $fullPath`n$detail"
        }
    }

    function Invoke-RedisDeleteBatch {
        param(
            [Parameter(Mandatory = $true)]
            [string[]]$Keys
        )

        if ($Keys.Count -eq 0) {
            return 0
        }

        # Keep each native command comfortably below Windows' command-line
        # length limit. Never pass the entire SCAN result to docker.exe at once.
        $dockerArgs = @('compose', 'exec', '-T', 'redis', 'redis-cli', 'DEL') + $Keys
        $nativeResult = Invoke-NativeCapture -FilePath 'docker' -Arguments $dockerArgs
        $output = @($nativeResult.Output)
        $exitCode = $nativeResult.ExitCode

        if ($exitCode -ne 0) {
            $detail = ($output | Out-String).Trim()
            throw "Redis DEL batch failed (exit code $exitCode). $detail"
        }

        $numericLines = @(
            $output |
                ForEach-Object { "$_".Trim() } |
                Where-Object { $_ -match '^\d+$' }
        )

        if ($numericLines.Count -eq 0) {
            $detail = ($output | Out-String).Trim()
            throw "Redis DEL did not return a deletion count. $detail"
        }

        return [int]$numericLines[-1]
    }

    # Preflight: verify database access and Redis before stopping application writers.
    Write-Host "`n[Preflight] Checking MySQL and Redis..." -ForegroundColor Yellow

    $mysqlPing = Invoke-DbScalar 'SELECT 1;'
    if ($mysqlPing -ne '1') {
        throw "MySQL preflight failed: SELECT 1 returned '$mysqlPing'."
    }

    $redisPingResult = Invoke-NativeCapture -FilePath 'docker' -Arguments @('compose', 'exec', '-T', 'redis', 'redis-cli', 'PING')
    $redisPing = @($redisPingResult.Output)
    $redisExitCode = $redisPingResult.ExitCode
    $redisPingText = [string]($redisPing | Select-Object -Last 1)
    if ($redisExitCode -ne 0 -or $redisPingText.Trim() -ne 'PONG') {
        $detail = ($redisPing | Out-String).Trim()
        throw "Redis preflight failed. $detail"
    }

    # Refuse to reset if the three expected demo accounts are not present
    # and correctly assigned.
    $demoUserCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user WHERE (username='admin' AND role='ADMIN') OR (username='teacher' AND role='TEACHER') OR (username='student' AND role='STUDENT');")
    if ($demoUserCount -ne 3) {
        throw "Expected exactly the admin/teacher/student demo accounts with matching roles; found $demoUserCount. No data was deleted."
    }

    # Stop application writers so no requests, scheduled jobs, or consumers race with cleanup.
    Write-Host "`n[1/7] Stopping API and Worker..." -ForegroundColor Yellow
    Invoke-DockerChecked -Arguments @('compose', 'stop', 'api', 'worker') -FailureMessage 'Could not stop api/worker'

    # Back up the database before destructive DML.
    Write-Host "`n[2/7] Backing up MySQL..." -ForegroundColor Yellow
    $backupDir = Join-Path $ProjectRoot 'backups'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backupPath = Join-Path $backupDir ("examforge-before-reset-{0}.sql" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    # --no-tablespaces avoids requiring the PROCESS privilege merely to dump
    # tablespace metadata. MYSQL_PWD avoids the insecure-password CLI warning.
    $safeDbPassword = $DbPassword.Replace('"', '""')
    $backupCommand = 'docker compose exec -T -e "MYSQL_PWD=' + $safeDbPassword + '"' +
        ' mysql mysqldump --default-character-set=utf8mb4 -u' + $DbUser +
        ' --single-transaction --routines --triggers --no-tablespaces ' + $DbName + ' > "' +
        $backupPath + '"'

    $backupResult = Invoke-NativeCapture -FilePath $env:ComSpec -Arguments @('/d', '/s', '/c', $backupCommand)
    $backupOutput = @($backupResult.Output)
    $backupExitCode = $backupResult.ExitCode

    foreach ($line in $backupOutput) {
        Write-Host $line
    }

    if (
        $backupExitCode -ne 0 -or
        -not (Test-Path -LiteralPath $backupPath) -or
        (Get-Item -LiteralPath $backupPath).Length -lt 1000 -or
        -not (Select-String -LiteralPath $backupPath -SimpleMatch 'CREATE TABLE' -Quiet)
    ) {
        $detail = ($backupOutput | Out-String).Trim()
        throw "Database backup failed or is incomplete. No cleanup SQL was executed. Check $backupPath. $detail"
    }

    Write-Host "Backup saved and basic integrity check passed: $backupPath" -ForegroundColor Green

    # Delete only ExamForge-owned Redis keys; never FLUSHDB/FLUSHALL.
    # Use bounded batches so Windows does not exceed its native command-line limit.
    Write-Host "`n[3/7] Removing stale ExamForge Redis cache/lock keys..." -ForegroundColor Yellow

    $redisKeys = @()
    foreach ($pattern in @('exam:*', 'lock:exam:start:*')) {
        $scanResult = Invoke-NativeCapture -FilePath 'docker' -Arguments @('compose', 'exec', '-T', 'redis', 'redis-cli', '--raw', '--scan', '--pattern', $pattern)
        $found = @($scanResult.Output)
        $scanExitCode = $scanResult.ExitCode

        if ($scanExitCode -ne 0) {
            $detail = ($found | Out-String).Trim()
            throw "Redis SCAN failed for pattern $pattern. $detail"
        }

        $redisKeys += @(
            $found |
                ForEach-Object { "$_".Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }

    $redisKeys = @($redisKeys | Select-Object -Unique)
    $deletedRedisKeys = 0

    if ($redisKeys.Count -gt 0) {
        $batch = New-Object 'System.Collections.Generic.List[string]'
        $batchCharacterCount = 0
        $maxBatchKeys = 50
        $maxBatchCharacters = 6000

        foreach ($key in $redisKeys) {
            if ($key.Length -gt $maxBatchCharacters) {
                throw "A Redis key is unexpectedly long; refusing to pass it as a Windows command-line argument."
            }

            if (
                $batch.Count -gt 0 -and
                (
                    $batch.Count -ge $maxBatchKeys -or
                    ($batchCharacterCount + $key.Length + 1) -gt $maxBatchCharacters
                )
            ) {
                $deletedRedisKeys += Invoke-RedisDeleteBatch -Keys ($batch.ToArray())
                $batch.Clear()
                $batchCharacterCount = 0
            }

            $batch.Add($key)
            $batchCharacterCount += ($key.Length + 1)
        }

        if ($batch.Count -gt 0) {
            $deletedRedisKeys += Invoke-RedisDeleteBatch -Keys ($batch.ToArray())
        }
    }

    Write-Host "Scanned $($redisKeys.Count) unique keys; deleted $deletedRedisKeys Redis keys." -ForegroundColor Green

    # From this point onward the database reset may have changed persistent data.
    # If a later step fails, leave API/Worker stopped for deliberate recovery.
    Write-Host "`n[4/7] Clearing historical exam data (question bank is preserved)..." -ForegroundColor Yellow
    $DatabaseResetStarted = $true
    Invoke-SqlFile -Path $ResetSqlPath

    Write-Host "`n[5/7] Adding 20 objective questions and creating the new test exam..." -ForegroundColor Yellow
    Invoke-SqlFile -Path $PrepareSqlPath

    # Load-test account creation is opt-in in the normal .env.example. Enable it
    # only for this controlled preparation run; the generated accounts remain local test data.
    $env:LOADTEST_USERS_ENABLED = 'true'

    # Start API/Worker with the updated image. API startup provisions
    # loadtest1001..loadtest2000.
    Write-Host "`n[6/7] Rebuilding and starting API/Worker..." -ForegroundColor Yellow
    Invoke-DockerChecked -Arguments @('compose', 'up', '-d', '--build', 'api', 'worker') -FailureMessage 'Could not rebuild/start api and worker'

    # Bring up any other Compose service that may have been stopped independently.
    Invoke-DockerChecked -Arguments @('compose', 'up', '-d') -FailureMessage 'Could not bring all Compose services up'

    Write-Host "Waiting for API health..." -ForegroundColor Yellow
    $healthy = $false

    for ($i = 0; $i -lt 60; $i++) {
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/actuator/health' -TimeoutSec 3 -UseBasicParsing
            if ($health.status -eq 'UP') {
                $healthy = $true
                break
            }
        }
        catch {
            # API is still starting.
        }

        Start-Sleep -Seconds 2
    }

    if (-not $healthy) {
        throw "API did not become healthy within 120 seconds. Check: docker compose logs --tail=200 api worker"
    }

    # Wait for CommandLineRunner account provisioning to finish and verify the exact account range.
    $accountCount = 0
    for ($i = 0; $i -lt 30; $i++) {
        $accountCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user WHERE username REGEXP '^loadtest[0-9]+$' AND CAST(SUBSTRING(username,9) AS UNSIGNED) BETWEEN 1001 AND 2000;")
        if ($accountCount -eq 1000) {
            break
        }
        Start-Sleep -Seconds 2
    }

    if ($accountCount -ne 1000) {
        throw "Expected 1000 load-test accounts loadtest1001..loadtest2000, found $accountCount. Check API logs."
    }

    $demoUserCountAfter = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user WHERE (username='admin' AND role='ADMIN') OR (username='teacher' AND role='TEACHER') OR (username='student' AND role='STUDENT');")
    if ($demoUserCountAfter -ne 3) {
        throw "Expected the three demo accounts after reset, found $demoUserCountAfter."
    }

    $unexpectedLoadtestCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user WHERE username LIKE 'loadtest%' AND NOT (CAST(SUBSTRING(username,9) AS UNSIGNED) BETWEEN 1001 AND 2000);")
    if ($unexpectedLoadtestCount -ne 0) {
        throw "Unexpected load-test accounts outside 1001..2000 remain: $unexpectedLoadtestCount"
    }

    $totalUsers = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user;")
    if ($totalUsers -ne 1003) {
        throw "Expected 1003 total users (3 demo + 1000 load-test), found $totalUsers."
    }

    $demoExamId = Invoke-DbScalar "SELECT id FROM exam WHERE title LIKE 'Java%' AND title NOT LIKE '%1000%' ORDER BY id DESC LIMIT 1;"
    if ([string]::IsNullOrWhiteSpace($demoExamId) -or $demoExamId -notmatch '^\d+$') {
        throw "Could not find the mixed-question demo exam."
    }

    $demoQuestionCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question WHERE exam_id=$demoExamId;")
    $demoSubjectiveCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question eq JOIN question_bank q ON q.id=eq.question_id WHERE eq.exam_id=$demoExamId AND q.type='SUBJECTIVE';")
    if ($demoQuestionCount -ne 10 -or $demoSubjectiveCount -ne 2) {
        throw "Expected the demo exam to contain 10 questions including 2 subjective questions; found questions=$demoQuestionCount, subjective=$demoSubjectiveCount."
    }

    $examId = Invoke-DbScalar "SELECT id FROM exam WHERE title LIKE 'Java%' AND title LIKE '%1000%' ORDER BY id DESC LIMIT 1;"
    if ([string]::IsNullOrWhiteSpace($examId) -or $examId -notmatch '^\d+$') {
        throw "Could not find the newly created 1000-user test exam."
    }

    $totalExamCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam;")
    if ($totalExamCount -ne 2) {
        throw "Expected exactly 2 exams (one mixed demo exam + one objective load-test exam), found $totalExamCount."
    }

    $questionCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question WHERE exam_id=$examId;")
    if ($questionCount -ne 10) {
        throw "Expected exactly 10 questions in the test exam, found $questionCount."
    }

    $subjectiveCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question eq JOIN question_bank q ON q.id=eq.question_id WHERE eq.exam_id=$examId AND q.type='SUBJECTIVE';")
    if ($subjectiveCount -ne 0) {
        throw "The dedicated load-test exam must be objective-only; found $subjectiveCount subjective questions."
    }

    # Use UTF-8 HEX for the Chinese knowledge-point value. This keeps the
    # validation query ASCII-only and compatible with Windows PowerShell 5.1.
    $newQuestionCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM question_bank WHERE HEX(knowledge_point)='4A617661E5908EE7ABAFE7BBBCE59088E883BDE58A9B2DE58E8BE6B58BE4B893E9A1B9';")
    if ($newQuestionCount -ne 20) {
        throw "Expected 20 new load-test question-bank items, found $newQuestionCount."
    }

    $totalQuestions = [int](Invoke-DbScalar "SELECT COUNT(*) FROM question_bank;")
    if ($totalQuestions -ne 30) {
        throw "Expected 30 total questions (10 existing + 20 new), found $totalQuestions."
    }

    # Final infrastructure verification: all eight expected containers must be running.
    Write-Host "`n[7/7] Verifying all containers and saving test configuration..." -ForegroundColor Yellow

    $requiredContainers = @(
        'examforge-mysql',
        'examforge-redis',
        'examforge-namesrv',
        'examforge-broker',
        'examforge-xxl-admin',
        'examforge-worker',
        'examforge-api',
        'examforge-web'
    )

    foreach ($containerName in $requiredContainers) {
        $statusResult = Invoke-NativeCapture -FilePath 'docker' -Arguments @('inspect', '--format', '{{.State.Status}}', $containerName)
        $statusOutput = @($statusResult.Output)
        $statusExitCode = $statusResult.ExitCode
        $containerStatus = [string]($statusOutput | Select-Object -Last 1)

        if ($statusExitCode -ne 0 -or $containerStatus.Trim() -ne 'running') {
            $detail = ($statusOutput | Out-String).Trim()
            throw "Required container $containerName is not running. Status='$containerStatus'. $detail"
        }

        Write-Host ("  {0}: running" -f $containerName) -ForegroundColor Green
    }

    $mysqlHealthResult = Invoke-NativeCapture -FilePath 'docker' -Arguments @('inspect', '--format', '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}', 'examforge-mysql')
    $mysqlHealthOutput = @($mysqlHealthResult.Output)
    $mysqlHealthExitCode = $mysqlHealthResult.ExitCode
    $mysqlHealth = [string]($mysqlHealthOutput | Select-Object -Last 1)

    if ($mysqlHealthExitCode -ne 0 -or $mysqlHealth.Trim() -ne 'healthy') {
        throw "MySQL container is running but not healthy. Health='$mysqlHealth'."
    }

    # Save the verified load-test exam ID for the JMeter runner.
    $idFileRoot = Join-Path $ProjectRoot 'performance-test-exam-id.txt'
    Set-Content -LiteralPath $idFileRoot -Value $examId -Encoding ASCII -NoNewline

    $jmeterConfigDir = Join-Path $ProjectRoot 'ExamForge_JMeter_Performance\config'
    New-Item -ItemType Directory -Force -Path $jmeterConfigDir | Out-Null
    Set-Content -LiteralPath (Join-Path $jmeterConfigDir 'exam-id.txt') -Value $examId -Encoding ASCII -NoNewline

    Write-Host "`nPreparation completed successfully." -ForegroundColor Green
    Write-Host "Demo users: admin / teacher / student (preserved)"
    Write-Host "Load-test users: loadtest1001 .. loadtest2000 (1000 accounts)"
    Write-Host "Total users: $totalUsers"
    Write-Host "Question bank: $totalQuestions questions (10 existing + 20 new objective questions)"
    Write-Host "Total exams: $totalExamCount"
    Write-Host "Demo exam ID: $demoExamId | Paper questions: $demoQuestionCount | Subjective questions: $demoSubjectiveCount"
    Write-Host "Load-test exam ID: $examId | Paper questions: $questionCount | Objective-only"
    Write-Host "Test account password: $LoadTestPassword"
    Write-Host "All 8 containers: running | MySQL health: healthy"
    Write-Host "Exam ID saved to: $idFileRoot"
    Write-Host "JMeter config saved to: $jmeterConfigDir\exam-id.txt"
    Write-Host "Database backup: $backupPath"
    Write-Host "`nOld RocketMQ messages are not purged. Their attempt IDs are not reused because AUTO_INCREMENT is preserved; stale TIMEOUT/GRADE messages for deleted attempts are harmless and will be acknowledged by the consumer."
}
catch {
    $failure = $_

    Write-Host "`nPREPARATION FAILED: $($failure.Exception.Message)" -ForegroundColor Red

    if (-not $DatabaseResetStarted) {
        Write-Host "Database reset SQL had not started. Attempting to restore API/Worker..." -ForegroundColor Yellow

        $recoveryResult = Invoke-NativeCapture -FilePath 'docker' -Arguments @('compose', 'up', '-d', 'api', 'worker')
        $recoveryOutput = @($recoveryResult.Output)
        $recoveryExitCode = $recoveryResult.ExitCode

        foreach ($line in $recoveryOutput) {
            Write-Host $line
        }

        if ($recoveryExitCode -eq 0) {
            Write-Host "API/Worker recovery command completed. Verify their health before continuing." -ForegroundColor Green
        }
        else {
            Write-Host "Automatic API/Worker recovery failed. Run: docker compose up -d api worker" -ForegroundColor Red
        }
    }
    else {
        Write-Host "The database reset had started. API/Worker were intentionally not restarted automatically; inspect the database and backup before recovery." -ForegroundColor Yellow
        if ($backupPath) {
            Write-Host "Backup: $backupPath" -ForegroundColor Yellow
        }
        Write-Host "After checking the database, recover with: docker compose up -d api worker" -ForegroundColor Yellow
    }

    throw $failure
}
finally {
    if ($null -eq $OriginalLoadtestUsersEnabled) {
        Remove-Item Env:LOADTEST_USERS_ENABLED -ErrorAction SilentlyContinue
    } else {
        $env:LOADTEST_USERS_ENABLED = $OriginalLoadtestUsersEnabled
    }
    Pop-Location
}
