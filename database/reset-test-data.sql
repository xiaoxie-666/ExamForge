-- ExamForge local test-environment reset.
-- Run only after backing up the database and stopping api/worker.
-- Keeps question_bank and the three demo accounts: admin, teacher, student.
-- Deletes all exam history, attempts, answers, grades, Outbox rows, exams,
-- and every user account other than the three demo accounts.
-- AUTO_INCREMENT values are intentionally NOT reset.

START TRANSACTION;

DELETE FROM grade_result;
DELETE FROM answer_record;
DELETE FROM exam_attempt;
DELETE FROM outbox_event;
DELETE FROM exam_question;
DELETE FROM exam;

DELETE FROM sys_user
WHERE username NOT IN ('admin', 'teacher', 'student');

COMMIT;

SELECT 'reset_complete' AS result;
SELECT COUNT(*) AS remaining_demo_users
FROM sys_user
WHERE username IN ('admin', 'teacher', 'student');
SELECT COUNT(*) AS remaining_exams FROM exam;
SELECT COUNT(*) AS preserved_questions FROM question_bank;
