[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot 'scripts/Import-ExamForgeEnv.ps1') -ProjectRoot $ProjectRoot
$DbName = if ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { 'examforge' }
$DbUser = if ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'examforge' }
$DbPassword = $env:MYSQL_PASSWORD
if ([string]::IsNullOrWhiteSpace($DbPassword)) { throw 'MYSQL_PASSWORD is required in .env.' }
Push-Location $ProjectRoot
try {
    function Invoke-DbScalar([string]$Query) {
        # Keep SQL ASCII-only for Windows PowerShell 5.1.
        # Windows PowerShell can promote native stderr (the harmless MySQL
        # password warning) to NativeCommandError when ErrorActionPreference=Stop.
        # Temporarily use Continue and merge stderr so the warning cannot abort
        # this read-only verifier. The native exit code still determines success.
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $result = & docker compose exec -T -e "MYSQL_PWD=$DbPassword" mysql mysql --default-character-set=utf8mb4 --batch --skip-column-names "-u$DbUser" $DbName -e $Query 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }

        if ($exitCode -ne 0) {
            $details = (@($result | ForEach-Object { [string]$_ }) -join ' ').Trim()
            throw "MySQL query failed (exit=$exitCode): $Query. Output: $details"
        }

        # The MySQL client prints a password warning on stderr. Ignore that
        # warning and return the final non-empty stdout scalar.
        $lines = @(
            $result |
                ForEach-Object { [string]$_ } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_) -and
                    $_ -notmatch 'mysql:\s*\[Warning\]'
                }
        )
        if ($lines.Count -eq 0) { return '' }
        return $lines[-1].Trim()
    }

    Write-Host 'ExamForge read-only environment verification' -ForegroundColor Cyan

    $demoUsers = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user WHERE (username='admin' AND role='ADMIN') OR (username='teacher' AND role='TEACHER') OR (username='student' AND role='STUDENT');")
    $loadUsers = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user WHERE username REGEXP '^loadtest[0-9]+$' AND CAST(SUBSTRING(username,9) AS UNSIGNED) BETWEEN 1001 AND 2000 AND role='STUDENT' AND status=1;")
    $totalUsers = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user;")
    $outsideUsers = [int](Invoke-DbScalar "SELECT COUNT(*) FROM sys_user WHERE username LIKE 'loadtest%' AND NOT (username REGEXP '^loadtest[0-9]+$' AND CAST(SUBSTRING(username,9) AS UNSIGNED) BETWEEN 1001 AND 2000);")

    # UTF-8 bytes for Java后端综合能力-压测专项. HEX() makes this ASCII-only.
    $newQuestions = [int](Invoke-DbScalar "SELECT COUNT(*) FROM question_bank WHERE HEX(knowledge_point)='4A617661E5908EE7ABAFE7BBBCE59088E883BDE58A9B2DE58E8BE6B58BE4B893E9A1B9';")
    $totalQuestions = [int](Invoke-DbScalar "SELECT COUNT(*) FROM question_bank;")

    $examCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam;")
    $demoExamId = Invoke-DbScalar "SELECT id FROM exam WHERE title LIKE 'Java%' AND title NOT LIKE '%1000%' ORDER BY id DESC LIMIT 1;"
    $testExamId = Invoke-DbScalar "SELECT id FROM exam WHERE title LIKE 'Java%' AND title LIKE '%1000%' ORDER BY id DESC LIMIT 1;"

    if ([string]::IsNullOrWhiteSpace($demoExamId) -or $demoExamId -notmatch '^\d+$') {
        throw 'Could not find the demo exam. No data was modified.'
    }
    if ([string]::IsNullOrWhiteSpace($testExamId) -or $testExamId -notmatch '^\d+$') {
        throw 'Could not find the 1000-user load-test exam. No data was modified.'
    }

    $demoPaperCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question WHERE exam_id=$demoExamId;")
    $demoSubjectiveCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question eq JOIN question_bank q ON q.id=eq.question_id WHERE eq.exam_id=$demoExamId AND q.type='SUBJECTIVE';")
    $testPaperCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question WHERE exam_id=$testExamId;")
    $testSubjectiveCount = [int](Invoke-DbScalar "SELECT COUNT(*) FROM exam_question eq JOIN question_bank q ON q.id=eq.question_id WHERE eq.exam_id=$testExamId AND q.type='SUBJECTIVE';")

    $checks = @(
        [PSCustomObject]@{ Check='Demo users'; Actual=$demoUsers; Expected=3; Pass=($demoUsers -eq 3) },
        [PSCustomObject]@{ Check='Enabled load-test users 1001..2000'; Actual=$loadUsers; Expected=1000; Pass=($loadUsers -eq 1000) },
        [PSCustomObject]@{ Check='Total users'; Actual=$totalUsers; Expected=1003; Pass=($totalUsers -eq 1003) },
        [PSCustomObject]@{ Check='Unexpected load-test users'; Actual=$outsideUsers; Expected=0; Pass=($outsideUsers -eq 0) },
        [PSCustomObject]@{ Check='New objective questions'; Actual=$newQuestions; Expected=20; Pass=($newQuestions -eq 20) },
        [PSCustomObject]@{ Check='Total question bank'; Actual=$totalQuestions; Expected=30; Pass=($totalQuestions -eq 30) },
        [PSCustomObject]@{ Check='Total exams'; Actual=$examCount; Expected=2; Pass=($examCount -eq 2) },
        [PSCustomObject]@{ Check='Demo exam questions'; Actual=$demoPaperCount; Expected=10; Pass=($demoPaperCount -eq 10) },
        [PSCustomObject]@{ Check='Demo exam subjective questions'; Actual=$demoSubjectiveCount; Expected=2; Pass=($demoSubjectiveCount -eq 2) },
        [PSCustomObject]@{ Check='Load-test exam questions'; Actual=$testPaperCount; Expected=10; Pass=($testPaperCount -eq 10) },
        [PSCustomObject]@{ Check='Load-test exam subjective questions'; Actual=$testSubjectiveCount; Expected=0; Pass=($testSubjectiveCount -eq 0) }
    )

    $checks | Format-Table -AutoSize
    $failed = @($checks | Where-Object { -not $_.Pass })
    if ($failed.Count -gt 0) {
        throw "Verification failed for $($failed.Count) check(s). No database data was modified. Do not rerun the destructive reset yet."
    }

    $rootIdFile = Join-Path $ProjectRoot 'performance-test-exam-id.txt'
    Set-Content -LiteralPath $rootIdFile -Value $testExamId -Encoding ASCII -NoNewline

    $jmeterConfigDir = Join-Path $ProjectRoot 'ExamForge_JMeter_Performance\config'
    if (Test-Path (Split-Path $jmeterConfigDir -Parent)) {
        New-Item -ItemType Directory -Force -Path $jmeterConfigDir | Out-Null
        Set-Content -LiteralPath (Join-Path $jmeterConfigDir 'exam-id.txt') -Value $testExamId -Encoding ASCII -NoNewline
    }

    Write-Host ''
    Write-Host 'Verification PASSED. No database rows were inserted, updated, or deleted.' -ForegroundColor Green
    Write-Host "Demo exam ID: $demoExamId"
    Write-Host "Load-test exam ID: $testExamId"
    Write-Host "Saved exam ID: $rootIdFile"
    if (Test-Path (Split-Path $jmeterConfigDir -Parent)) {
        Write-Host "Saved JMeter config: $(Join-Path $jmeterConfigDir 'exam-id.txt')"
    } else {
        Write-Host 'JMeter project folder not found under the main project; copy the load-test exam ID into its config/exam-id.txt.' -ForegroundColor Yellow
    }
} finally {
    Pop-Location
}
