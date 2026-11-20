-- Idempotently add 20 objective questions for the Java backend assessment.
-- The 20-question pool contains 10 SINGLE, 5 MULTIPLE and 5 JUDGE questions.
-- The test paper selects 6 SINGLE, 2 MULTIPLE and 2 JUDGE questions (50 points).
-- Existing 10 questions are preserved. No question is deleted or overwritten.
START TRANSACTION;

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', 'Java 中，以下哪种集合更适合在多线程环境下进行并发读写？', JSON_ARRAY('A. HashMap', 'B. ConcurrentHashMap', 'C. ArrayList', 'D. TreeMap'), 'B', 'ConcurrentHashMap 提供面向并发场景的线程安全访问能力。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='Java 中，以下哪种集合更适合在多线程环境下进行并发读写？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', 'Spring 中，@Transactional 注解默认使用哪种事务传播行为？', JSON_ARRAY('A. REQUIRES_NEW', 'B. REQUIRED', 'C. SUPPORTS', 'D. NEVER'), 'B', 'REQUIRED 表示当前存在事务时加入当前事务，不存在时创建新事务。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='Spring 中，@Transactional 注解默认使用哪种事务传播行为？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', 'MySQL InnoDB 存储引擎默认的事务隔离级别是什么？', JSON_ARRAY('A. READ UNCOMMITTED', 'B. READ COMMITTED', 'C. REPEATABLE READ', 'D. SERIALIZABLE'), 'C', 'InnoDB 默认隔离级别为 REPEATABLE READ。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='MySQL InnoDB 存储引擎默认的事务隔离级别是什么？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', '执行 Redis 命令 SET lock value NX EX 60，主要表达什么含义？', JSON_ARRAY('A. 无论键是否存在都覆盖并永久保存', 'B. 仅当键已存在时设置并保存 60 秒', 'C. 仅当键不存在时设置，并设置 60 秒过期时间', 'D. 删除键并等待 60 秒'), 'C', 'NX 表示键不存在时才设置，EX 60 表示过期时间为 60 秒。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='执行 Redis 命令 SET lock value NX EX 60，主要表达什么含义？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', '在 exam_attempt 表上建立 (exam_id,user_id) 联合唯一索引，最直接的作用是什么？', JSON_ARRAY('A. 保证每场考试只能有一名考生', 'B. 防止同一考生重复创建同一场考试的记录', 'C. 保证所有考生的考试记录 ID 连续', 'D. 自动完成考试阅卷'), 'B', '联合唯一索引从数据库层面保证同一考试与同一考生的组合只出现一次。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='在 exam_attempt 表上建立 (exam_id,user_id) 联合唯一索引，最直接的作用是什么？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', 'HTTP 状态码 429 通常表示什么？', JSON_ARRAY('A. 未认证', 'B. 禁止访问', 'C. 资源不存在', 'D. 请求过于频繁'), 'D', '429 Too Many Requests 表示客户端在一定时间内发送了过多请求。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='HTTP 状态码 429 通常表示什么？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', 'JWT 常用于无状态身份认证，其典型特点是什么？', JSON_ARRAY('A. 服务端必须为每个用户保存 HTTP Session', 'B. 服务端可校验令牌签名和有效期来识别身份', 'C. JWT 默认会加密全部载荷内容', 'D. JWT 不能携带用户身份信息'), 'B', 'JWT 通常通过签名保证完整性，服务端校验签名和有效期即可完成身份识别；签名不等于加密。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='JWT 常用于无状态身份认证，其典型特点是什么？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', '事务 Outbox 模式主要解决什么问题？', JSON_ARRAY('A. 将业务数据写入和事件记录写入放在同一数据库事务中', 'B. 让数据库事务直接替代消息队列', 'C. 保证消息消费者永远不会重复消费', 'D. 将所有业务数据只保存在 Redis'), 'A', 'Outbox 将业务变更与待发布事件记录写入同一个本地数据库事务，再由发布器异步投递消息。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='事务 Outbox 模式主要解决什么问题？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', '在 MySQL 事务中执行 SELECT ... FOR UPDATE，主要用途是什么？', JSON_ARRAY('A. 对查询到的记录加锁，避免并发事务同时修改相关记录', 'B. 永久锁定整张数据库表', 'C. 自动提交当前事务', 'D. 绕过事务隔离机制'), 'A', 'SELECT FOR UPDATE 在事务中对匹配记录加排他锁，锁通常在事务提交或回滚时释放。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='在 MySQL 事务中执行 SELECT ... FOR UPDATE，主要用途是什么？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'SINGLE', 'Redis Lua 脚本在 Redis 服务端执行时具有哪项重要特性？', JSON_ARRAY('A. 脚本中的命令会被其他客户端命令随意插入', 'B. 脚本只能读取数据，不能修改数据', 'C. 脚本执行期间具有原子性，不会与其他命令交错执行', 'D. 脚本执行结果不会影响 Redis 数据'), 'C', 'Redis 将 Lua 脚本作为一个原子执行单元处理，脚本执行期间不会穿插执行其他客户端命令。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='Redis Lua 脚本在 Redis 服务端执行时具有哪项重要特性？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'MULTIPLE', '数据库事务 ACID 特性包括哪些？', JSON_ARRAY('A. 原子性（Atomicity）', 'B. 一致性（Consistency）', 'C. 隔离性（Isolation）', 'D. 持久性（Durability）'), 'A,B,C,D', 'ACID 分别指原子性、一致性、隔离性和持久性。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='数据库事务 ACID 特性包括哪些？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'MULTIPLE', 'Java volatile 关键字能够提供哪些语义？', JSON_ARRAY('A. 保证变量写入对其他线程的可见性', 'B. 对相关操作提供一定的有序性约束', 'C. 自动保证 i++ 这类复合操作的原子性', 'D. 替代所有 synchronized 锁'), 'A,B', 'volatile 主要提供可见性和有序性保证，但不能保证 i++ 等复合操作的原子性。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='Java volatile 关键字能够提供哪些语义？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'MULTIPLE', '为了提高消息消费链路的可靠性，消费者侧通常需要考虑哪些机制？', JSON_ARRAY('A. 基于业务唯一键实现幂等', 'B. 对可恢复异常进行重试', 'C. 对多次失败的消息进行死信处理', 'D. 假设消息队列绝不会重复投递'), 'A,B,C', '消费幂等、合理重试和死信处理是消息可靠性设计的重要组成部分。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='为了提高消息消费链路的可靠性，消费者侧通常需要考虑哪些机制？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'MULTIPLE', '使用 JMeter 评估接口性能时，以下哪些指标具有代表性？', JSON_ARRAY('A. 吞吐量（TPS）', 'B. 请求错误率', 'C. P95/P99 响应时间', 'D. 项目代码总行数'), 'A,B,C', 'TPS、错误率和高分位响应时间可以共同反映系统处理能力与稳定性。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='使用 JMeter 评估接口性能时，以下哪些指标具有代表性？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'MULTIPLE', '针对数据库并发写入，以下哪些措施可以用于降低数据竞争风险？', JSON_ARRAY('A. 合理使用唯一索引约束业务唯一性', 'B. 使用 version 字段进行乐观锁更新', 'C. 在事务中使用 SELECT FOR UPDATE', 'D. 忽略事务边界并依赖请求到达顺序'), 'A,B,C', '唯一约束、乐观锁和行级锁分别从数据约束与并发控制角度降低竞争风险。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='针对数据库并发写入，以下哪些措施可以用于降低数据竞争风险？');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'JUDGE', 'Redis Lua 脚本在 Redis 中执行时具有原子性。', JSON_ARRAY('正确', '错误'), '正确', 'Redis 保证 Lua 脚本作为整体执行，不会与其他客户端命令交错。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='Redis Lua 脚本在 Redis 中执行时具有原子性。');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'JUDGE', 'JWT 的载荷部分默认经过加密，因此客户端无法读取其中的声明信息。', JSON_ARRAY('正确', '错误'), '错误', '常见 JWT 是 Base64URL 编码并进行签名，载荷默认可读取；签名不代表加密。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='JWT 的载荷部分默认经过加密，因此客户端无法读取其中的声明信息。');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'JUDGE', '事务 Outbox 模式可以将业务数据变更与待发布事件记录放在同一个本地数据库事务中提交。', JSON_ARRAY('正确', '错误'), '正确', '两类记录在同一数据库事务中提交，可以避免业务提交成功但事件记录未落库的问题。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='事务 Outbox 模式可以将业务数据变更与待发布事件记录放在同一个本地数据库事务中提交。');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'JUDGE', 'RocketMQ 消费者可能遇到重复投递，因此业务处理通常需要考虑幂等性。', JSON_ARRAY('正确', '错误'), '正确', '消息重复投递是分布式消息系统需要考虑的情况，消费者应通过业务键或唯一约束实现幂等。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='RocketMQ 消费者可能遇到重复投递，因此业务处理通常需要考虑幂等性。');

INSERT INTO question_bank (type, content, options_json, correct_answer, analysis, difficulty, knowledge_point, default_score, created_by, create_time, update_time)
SELECT 'JUDGE', '使用 Redisson RLock 且未显式指定租约时间时，可以利用 Watchdog 机制自动续期锁。', JSON_ARRAY('正确', '错误'), '正确', 'Redisson 在未指定 leaseTime 的常见加锁方式下，会通过 Watchdog 在持锁期间续期。', 'MEDIUM', 'Java后端综合能力-压测专项', 5.00, (SELECT id FROM sys_user WHERE username='admin' LIMIT 1), NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM question_bank WHERE content='使用 Redisson RLock 且未显式指定租约时间时，可以利用 Watchdog 机制自动续期锁。');

COMMIT;


-- Create a mixed-question demo exam from the original 10-question bank.
-- It keeps the subjective questions available for a manual-grading demonstration.
START TRANSACTION;

INSERT INTO exam
(title, description, status, start_time, end_time, duration_minutes, created_by, create_time, update_time)
SELECT
  'Java 后端基础能力测评（功能演示）',
  '功能演示考试，包含客观题与主观题，可分别演示自动阅卷和教师人工评分。',
  'PUBLISHED',
  DATE_SUB(NOW(), INTERVAL 5 MINUTE),
  DATE_ADD(NOW(), INTERVAL 30 DAY),
  60,
  (SELECT id FROM sys_user WHERE username='admin' LIMIT 1),
  NOW(),
  NOW()
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM exam
  WHERE title='Java 后端基础能力测评（功能演示）'
);

SET @demo_exam_id = (
  SELECT id FROM exam
  WHERE title='Java 后端基础能力测评（功能演示）'
  ORDER BY id DESC LIMIT 1
);

INSERT IGNORE INTO exam_question (exam_id, question_id, sort_order, score)
SELECT @demo_exam_id, q.id, q.seq, q.default_score
FROM (
  SELECT id, default_score,
         ROW_NUMBER() OVER (ORDER BY id ASC) AS seq
  FROM question_bank
  WHERE knowledge_point='Java 后端基础'
) q
WHERE q.seq <= 10;

UPDATE exam
SET status='PUBLISHED',
    start_time=DATE_SUB(NOW(), INTERVAL 5 MINUTE),
    end_time=DATE_ADD(NOW(), INTERVAL 30 DAY),
    duration_minutes=60,
    update_time=NOW()
WHERE id=@demo_exam_id;

COMMIT;

-- Create or refresh the dedicated 1000-user load-test exam. It contains
-- 6 SINGLE, 2 MULTIPLE, and 2 JUDGE questions from the new objective pool.
START TRANSACTION;

INSERT INTO exam
(title, description, status, start_time, end_time, duration_minutes, created_by, create_time, update_time)
SELECT
  'Java 后端综合能力测评（1000人压测专用）',
  '仅包含客观题，用于验证 1000 名虚拟考生的开考、逐题保存、交卷及 RocketMQ 异步阅卷链路。',
  'PUBLISHED',
  DATE_SUB(NOW(), INTERVAL 5 MINUTE),
  DATE_ADD(NOW(), INTERVAL 30 DAY),
  60,
  (SELECT id FROM sys_user WHERE username='admin' LIMIT 1),
  NOW(),
  NOW()
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM exam
  WHERE title='Java 后端综合能力测评（1000人压测专用）'
);

SET @test_exam_id = (
  SELECT id FROM exam
  WHERE title='Java 后端综合能力测评（1000人压测专用）'
  ORDER BY id DESC LIMIT 1
);

INSERT IGNORE INTO exam_question (exam_id, question_id, sort_order, score)
SELECT @test_exam_id, selected.id, selected.sort_order, selected.default_score
FROM (
  SELECT id, default_score, rn AS sort_order
  FROM (
    SELECT id, default_score,
           ROW_NUMBER() OVER (ORDER BY id ASC) AS rn
    FROM question_bank
    WHERE knowledge_point='Java后端综合能力-压测专项' AND type='SINGLE'
  ) single_questions
  WHERE rn <= 6

  UNION ALL

  SELECT id, default_score, 6 + rn AS sort_order
  FROM (
    SELECT id, default_score,
           ROW_NUMBER() OVER (ORDER BY id ASC) AS rn
    FROM question_bank
    WHERE knowledge_point='Java后端综合能力-压测专项' AND type='MULTIPLE'
  ) multiple_questions
  WHERE rn <= 2

  UNION ALL

  SELECT id, default_score, 8 + rn AS sort_order
  FROM (
    SELECT id, default_score,
           ROW_NUMBER() OVER (ORDER BY id ASC) AS rn
    FROM question_bank
    WHERE knowledge_point='Java后端综合能力-压测专项' AND type='JUDGE'
  ) judge_questions
  WHERE rn <= 2
) selected;

UPDATE exam
SET status='PUBLISHED',
    start_time=DATE_SUB(NOW(), INTERVAL 5 MINUTE),
    end_time=DATE_ADD(NOW(), INTERVAL 30 DAY),
    duration_minutes=60,
    update_time=NOW()
WHERE id=@test_exam_id;

COMMIT;

SELECT id, title, status, start_time, end_time, duration_minutes
FROM exam WHERE id=@demo_exam_id;

SELECT COUNT(*) AS demo_paper_question_count
FROM exam_question WHERE exam_id=@demo_exam_id;

SELECT id, title, status, start_time, end_time, duration_minutes
FROM exam WHERE id=@test_exam_id;

SELECT COUNT(*) AS loadtest_paper_question_count
FROM exam_question WHERE exam_id=@test_exam_id;

SELECT q.type, COUNT(*) AS demo_question_count
FROM exam_question eq JOIN question_bank q ON q.id=eq.question_id
WHERE eq.exam_id=@demo_exam_id
GROUP BY q.type ORDER BY q.type;

SELECT q.type, COUNT(*) AS loadtest_question_count
FROM exam_question eq JOIN question_bank q ON q.id=eq.question_id
WHERE eq.exam_id=@test_exam_id
GROUP BY q.type ORDER BY q.type;

SELECT type, COUNT(*) AS question_count
FROM question_bank
WHERE knowledge_point='Java后端综合能力-压测专项'
GROUP BY type ORDER BY type;
