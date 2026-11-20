[CmdletBinding()]
param(
    [ValidateRange(1,2147483647)][int]$ExamId = 0,
    [ValidateRange(1001,2000)][int]$AccountStart = 1001,
    [ValidateRange(1,1000)][int]$AccountCount = 1000,
    [ValidateRange(10,3600)][int]$TimeoutSeconds = 1800,
    [ValidateRange(1,60)][int]$PollSeconds = 5,
    [string]$RunDirectory = ''
)

$ErrorActionPreference = 'Stop'
$packageRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $packageRoot
. (Join-Path $projectRoot 'scripts/Import-ExamForgeEnv.ps1') -ProjectRoot $projectRoot
$DbName = if ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { 'examforge' }
$DbUser = if ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'examforge' }
$DbPassword = $env:MYSQL_PASSWORD
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw 'MYSQL_PASSWORD is required in .env.' }
$lastAccount = $AccountStart + $AccountCount - 1
if ($lastAccount -gt 2000) { throw 'Account range exceeds loadtest2000.' }

if ($ExamId -eq 0) {
    $examIdFile = Join-Path $packageRoot 'config\exam-id.txt'
    if (-not (Test-Path $examIdFile)) {
        $examIdFile = Join-Path $projectRoot 'performance-test-exam-id.txt'
    }
    if (-not (Test-Path $examIdFile)) { throw 'Exam ID file not found. Run prepare-test-environment.ps1 first.' }
    $ExamId = [int](Get-Content -LiteralPath $examIdFile -Raw).Trim()
}
if ($ExamId -le 0) { throw 'ExamId must be positive.' }

if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $packageRoot 'results') -Directory -Filter "full-exam$ExamId-$($AccountCount)users-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($candidate) { $RunDirectory = $candidate.FullName }
}
if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
    $RunDirectory = Join-Path $packageRoot 'results'
}
New-Item -ItemType Directory -Force -Path $RunDirectory | Out-Null

Push-Location $projectRoot
try {
    function Get-DbSnapshot {
        $query = @"
SELECT
 (SELECT COUNT(*) FROM exam_attempt a JOIN sys_user u ON u.id=a.user_id
   WHERE a.exam_id=$ExamId AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount),
 (SELECT COUNT(*) FROM exam_attempt a JOIN sys_user u ON u.id=a.user_id
   WHERE a.exam_id=$ExamId AND a.status='SUBMITTED'
     AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount),
 (SELECT COUNT(*) FROM answer_record ar
   JOIN exam_attempt a ON a.id=ar.attempt_id JOIN sys_user u ON u.id=a.user_id
   WHERE a.exam_id=$ExamId AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount),
 (SELECT COUNT(*) FROM grade_result g
   JOIN exam_attempt a ON a.id=g.attempt_id JOIN sys_user u ON u.id=a.user_id
   WHERE a.exam_id=$ExamId AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount),
 (SELECT COUNT(*) FROM grade_result g
   JOIN exam_attempt a ON a.id=g.attempt_id JOIN sys_user u ON u.id=a.user_id
   WHERE a.exam_id=$ExamId AND g.status='COMPLETED'
     AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount),
 (SELECT COUNT(*) FROM grade_result g
   JOIN exam_attempt a ON a.id=g.attempt_id JOIN sys_user u ON u.id=a.user_id
   WHERE a.exam_id=$ExamId AND g.status='PENDING_MANUAL'
     AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount),
 (SELECT COUNT(*) FROM outbox_event oe
   JOIN exam_attempt a ON a.id=CAST(JSON_UNQUOTE(JSON_EXTRACT(oe.payload,'$.attemptId')) AS UNSIGNED)
   JOIN sys_user u ON u.id=a.user_id
   WHERE a.exam_id=$ExamId AND oe.event_type='GRADE' AND oe.status='SENT'
     AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN $AccountStart AND $lastAccount),
 (SELECT COUNT(*) FROM exam_question WHERE exam_id=$ExamId);
"@
        $raw = & docker compose exec -T -e "MYSQL_PWD=$DbPassword" mysql mysql --batch --skip-column-names "-u$DbUser" $DbName -e $query
        if ($LASTEXITCODE -ne 0) { throw 'Unable to query MySQL for post-run verification.' }
        $line = @($raw | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
        if ($line.Count -eq 0) { throw 'MySQL returned no verification row.' }
        $parts = $line[0] -split "`t"
        if ($parts.Count -ne 8) { throw "Unexpected MySQL verification output: $($line[0])" }
        return [PSCustomObject]@{
            Attempts = [int]$parts[0]
            Submitted = [int]$parts[1]
            AnswerRecords = [int]$parts[2]
            GradeRows = [int]$parts[3]
            CompletedGrades = [int]$parts[4]
            PendingManual = [int]$parts[5]
            GradeOutboxSent = [int]$parts[6]
            PaperQuestions = [int]$parts[7]
        }
    }

    $expectedAnswers = $null
    $snapshot = $null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Host "Waiting for asynchronous grading: exam=$ExamId, accounts=$AccountStart..$lastAccount, expected users=$AccountCount" -ForegroundColor Cyan

    do {
        $snapshot = Get-DbSnapshot
        if ($snapshot.PaperQuestions -le 0) {
            throw "Exam $ExamId has no questions. Verify the selected exam before evaluating the run."
        }
        $expectedAnswers = $AccountCount * $snapshot.PaperQuestions
        $complete = (
            $snapshot.Attempts -eq $AccountCount -and
            $snapshot.Submitted -eq $AccountCount -and
            $snapshot.AnswerRecords -ge $expectedAnswers -and
            $snapshot.GradeRows -eq $AccountCount -and
            $snapshot.CompletedGrades -eq $AccountCount -and
            $snapshot.PendingManual -eq 0 -and
            $snapshot.GradeOutboxSent -eq $AccountCount
        )
        if ($complete) { break }
        if ((Get-Date) -ge $deadline) { break }
        Write-Host ("Progress: attempts {0}/{1}, submitted {2}/{1}, answers {3}/{4}, completed grades {5}/{1}, GRADE Outbox SENT {6}/{1}" -f `
            $snapshot.Attempts,$AccountCount,$snapshot.Submitted,$snapshot.AnswerRecords,$expectedAnswers,$snapshot.CompletedGrades,$snapshot.GradeOutboxSent)
        Start-Sleep -Seconds $PollSeconds
    } while ((Get-Date) -lt $deadline)

    $report = @(
        "ExamForge Full-flow Verification",
        "ExamId=$ExamId",
        "AccountRange=loadtest$('{0:D4}' -f $AccountStart)..loadtest$('{0:D4}' -f $lastAccount)",
        "ExpectedUsers=$AccountCount",
        "PaperQuestions=$($snapshot.PaperQuestions)",
        "ExpectedAnswerRecords=$expectedAnswers",
        "Attempts=$($snapshot.Attempts)",
        "SubmittedAttempts=$($snapshot.Submitted)",
        "AnswerRecords=$($snapshot.AnswerRecords)",
        "GradeRows=$($snapshot.GradeRows)",
        "CompletedGrades=$($snapshot.CompletedGrades)",
        "PendingManualGrades=$($snapshot.PendingManual)",
        "GradeOutboxSent=$($snapshot.GradeOutboxSent)",
        "VerifiedAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    )
    $reportPath = Join-Path $RunDirectory 'verification.txt'
    $report | Set-Content -LiteralPath $reportPath -Encoding UTF8
    $snapshot | Export-Csv -LiteralPath (Join-Path $RunDirectory 'verification.csv') -NoTypeInformation -Encoding UTF8

    Write-Host ''
    $snapshot | Format-List
    if (-not $complete) {
        throw "Full-flow verification incomplete after $TimeoutSeconds seconds. See $reportPath and inspect API/Worker/MySQL logs."
    }
    Write-Host "Verified: all $AccountCount candidates submitted, saved at least $expectedAnswers answer records, and received COMPLETED grades." -ForegroundColor Green
    Write-Host "Verification saved: $reportPath" -ForegroundColor Green
} finally {
    Pop-Location
}
