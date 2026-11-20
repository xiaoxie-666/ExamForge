-- ExamForge full-flow verification for the dedicated load-test account pool.
-- Set @exam_id to the ID printed by scripts/prepare-test-environment.ps1.
-- The test exam is objective-only and should contain 10 questions.
SET @exam_id = 0;
SET @account_start = 1001;
SET @account_end = 2000;

-- 1. Target exam and paper size.
SELECT id, title, status, start_time, end_time, duration_minutes
FROM exam WHERE id = @exam_id;
SELECT COUNT(*) AS paper_question_count
FROM exam_question WHERE exam_id = @exam_id;

-- 2. Candidate attempt totals and status distribution.
SELECT COUNT(*) AS total_attempts,
       COUNT(DISTINCT a.user_id) AS unique_candidates,
       SUM(a.status = 'SUBMITTED') AS submitted_attempts,
       SUM(a.status = 'IN_PROGRESS') AS in_progress_attempts
FROM exam_attempt a
JOIN sys_user u ON u.id = a.user_id
WHERE a.exam_id = @exam_id
  AND CAST(SUBSTRING(u.username, 9) AS UNSIGNED) BETWEEN @account_start AND @account_end;

SELECT a.status AS attempt_status, COUNT(*) AS total
FROM exam_attempt a
JOIN sys_user u ON u.id = a.user_id
WHERE a.exam_id = @exam_id
  AND CAST(SUBSTRING(u.username, 9) AS UNSIGNED) BETWEEN @account_start AND @account_end
GROUP BY a.status ORDER BY a.status;

-- 3. Answer coverage. For a complete run, each submitted attempt should have all paper answers.
SELECT COUNT(*) AS total_answer_records,
       (SELECT COUNT(*) FROM exam_attempt a
        JOIN sys_user u ON u.id=a.user_id
        WHERE a.exam_id=@exam_id AND a.status='SUBMITTED'
          AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN @account_start AND @account_end) *
       (SELECT COUNT(*) FROM exam_question WHERE exam_id=@exam_id) AS expected_answer_records
FROM answer_record ar
JOIN exam_attempt a ON a.id=ar.attempt_id
JOIN sys_user u ON u.id=a.user_id
WHERE a.exam_id=@exam_id
  AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN @account_start AND @account_end;

-- 4. Async grading. The dedicated test paper contains no subjective questions,
-- so all successful submissions should eventually become COMPLETED.
SELECT g.status AS grade_status, COUNT(*) AS total
FROM grade_result g
JOIN exam_attempt a ON a.id=g.attempt_id
JOIN sys_user u ON u.id=a.user_id
WHERE a.exam_id=@exam_id
  AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN @account_start AND @account_end
GROUP BY g.status ORDER BY g.status;

-- 5. GRADE Outbox delivery status.
SELECT oe.status AS outbox_status, COUNT(*) AS total
FROM outbox_event oe
JOIN exam_attempt a
  ON a.id = CAST(JSON_UNQUOTE(JSON_EXTRACT(oe.payload, '$.attemptId')) AS UNSIGNED)
JOIN sys_user u ON u.id=a.user_id
WHERE a.exam_id=@exam_id
  AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN @account_start AND @account_end
  AND oe.event_type='GRADE'
GROUP BY oe.status ORDER BY oe.status;

-- 6. Final consistency checks.
SELECT COUNT(*) AS submitted_without_grade
FROM exam_attempt a
JOIN sys_user u ON u.id=a.user_id
LEFT JOIN grade_result g ON g.attempt_id=a.id
WHERE a.exam_id=@exam_id AND a.status='SUBMITTED'
  AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN @account_start AND @account_end
  AND g.id IS NULL;

SELECT COUNT(*) AS submitted_with_incomplete_answer_set
FROM exam_attempt a
JOIN sys_user u ON u.id=a.user_id
WHERE a.exam_id=@exam_id AND a.status='SUBMITTED'
  AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN @account_start AND @account_end
  AND (SELECT COUNT(*) FROM answer_record ar WHERE ar.attempt_id=a.id)
      < (SELECT COUNT(*) FROM exam_question eq WHERE eq.exam_id=a.exam_id);

-- 7. Recent samples for manual spot checks.
SELECT a.id AS attempt_id, u.username, a.status, a.started_at, a.submitted_at,
       g.objective_score, g.subjective_score, g.total_score, g.status AS grade_status
FROM exam_attempt a
JOIN sys_user u ON u.id=a.user_id
LEFT JOIN grade_result g ON g.attempt_id=a.id
WHERE a.exam_id=@exam_id
  AND CAST(SUBSTRING(u.username,9) AS UNSIGNED) BETWEEN @account_start AND @account_end
ORDER BY a.id DESC LIMIT 20;
