package com.examforge.attempt;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.examforge.attempt.entity.AnswerRecordEntity;
import com.examforge.attempt.entity.ExamAttemptEntity;
import com.examforge.attempt.mapper.AnswerRecordMapper;
import com.examforge.attempt.mapper.ExamAttemptMapper;
import com.examforge.common.ApiDtos.*;
import com.examforge.common.BusinessException;
import com.examforge.exam.entity.ExamEntity;
import com.examforge.exam.mapper.ExamMapper;
import com.examforge.exam.mapper.ExamAdmissionRow;
import com.examforge.exam.mapper.ExamQuestionDetailRow;
import com.examforge.exam.mapper.ExamQuestionMapper;
import com.examforge.grading.entity.GradeResultEntity;
import com.examforge.grading.mapper.GradeResultMapper;
import com.examforge.mq.entity.OutboxEventEntity;
import com.examforge.mq.mapper.OutboxEventMapper;
import com.examforge.user.entity.UserEntity;
import com.examforge.user.mapper.UserMapper;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

@Service
public class ExamAttemptService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    /**
     * Atomic admission gate:
     * 1. Exam must be published.
     * 2. Current time must be inside the exam time window.
     * 3. Candidate account must be active.
     * 4. A candidate can acquire only one admission marker for this exam.
     *
     * MySQL remains the source of truth. The admission marker is an additional
     * cross-instance guard; the unique (exam_id, user_id) key is the final fence.
     */
    private static final DefaultRedisScript<Long> ADMIT_EXAM = new DefaultRedisScript<>("""
            if ARGV[1] ~= 'PUBLISHED' then
                return -1
            end

            local nowTs = tonumber(ARGV[2])
            local startTs = tonumber(ARGV[3])
            local endTs = tonumber(ARGV[4])
            local userStatus = tonumber(ARGV[5])

            if userStatus ~= 1 then
                return -4
            end
            if nowTs < startTs then
                return -2
            end
            if nowTs >= endTs then
                return -3
            end

            -- The caller holds the distributed exam/user Redisson lock and has
            -- already checked MySQL for an existing attempt. Remove an orphaned
            -- marker and install the new token atomically in this single script.
            redis.call('DEL', KEYS[1])
            local result = redis.call('SET', KEYS[1], ARGV[6], 'NX', 'EX', ARGV[7])
            if not result then
                return 0
            end
            return 1
            """, Long.class);

    private static final DefaultRedisScript<Long> FINALIZE_ADMISSION = new DefaultRedisScript<>("""
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                redis.call('SET', KEYS[1], 'A:' .. ARGV[2], 'EX', ARGV[3])
                return 1
            end
            return 0
            """, Long.class);

    private static final DefaultRedisScript<Long> RELEASE_ADMISSION = new DefaultRedisScript<>("""
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                return redis.call('DEL', KEYS[1])
            end
            return 0
            """, Long.class);

    /**
     * Cache writes are version-aware. An older after-commit callback can never
     * overwrite a newer answer already written to Redis.
     * Cache value format: {version}|{URL-safe-base64(answer)}.
     */
    private static final DefaultRedisScript<Long> CACHE_ANSWER = new DefaultRedisScript<>("""
            local current = redis.call('HGET', KEYS[1], ARGV[1])
            local incomingVersion = tonumber(ARGV[2])

            if current then
                local separator = string.find(current, '|', 1, true)
                if separator then
                    local currentVersion = tonumber(string.sub(current, 1, separator - 1))
                    if currentVersion and currentVersion > incomingVersion then
                        return 0
                    end
                end
            end

            redis.call('HSET', KEYS[1], ARGV[1], ARGV[3])
            redis.call('EXPIRE', KEYS[1], tonumber(ARGV[4]))
            return 1
            """, Long.class);

    private final ExamAttemptMapper attempts;
    private final AnswerRecordMapper answers;
    private final ExamMapper exams;
    private final ExamQuestionMapper links;
    private final OutboxEventMapper outbox;
    private final GradeResultMapper grades;
    private final UserMapper users;
    private final ObjectMapper json;
    private final StringRedisTemplate redis;
    private final RedissonClient redisson;

    public ExamAttemptService(
            ExamAttemptMapper attempts,
            AnswerRecordMapper answers,
            ExamMapper exams,
            ExamQuestionMapper links,
            OutboxEventMapper outbox,
            GradeResultMapper grades,
            UserMapper users,
            ObjectMapper json,
            StringRedisTemplate redis,
            RedissonClient redisson) {
        this.attempts = attempts;
        this.answers = answers;
        this.exams = exams;
        this.links = links;
        this.outbox = outbox;
        this.grades = grades;
        this.users = users;
        this.json = json;
        this.redis = redis;
        this.redisson = redisson;
    }

    /**
     * Candidate admission uses three layers:
     * Redisson RLock protects the per-candidate DB creation critical section across instances;
     * Redis Lua performs the admission checks and marker write atomically;
     * MySQL shared exam/user-row locks let candidates enter concurrently while serializing
     * against admin close/delete and account-status changes; uk_exam_user is the final fence.
     */
    @Transactional
    public AttemptView start(Long examId, Long userId) {
        String lockName = "lock:exam:start:" + examId + ":" + userId;
        RLock lock = redisson.getLock(lockName);
        boolean locked;

        try {
            // No explicit lease time: Redisson Watchdog renews the lock while
            // this transaction is alive, avoiding premature expiry on slow DB work.
            locked = lock.tryLock(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new BusinessException(503, "考试准入正在处理中，请稍后重试");
        }

        if (!locked) {
            ExamAttemptEntity concurrentAttempt = attempts.selectByExamAndUser(examId, userId);
            if (concurrentAttempt != null) {
                return detail(concurrentAttempt);
            }
            throw new BusinessException(409, "考试记录正在创建，请稍后重试");
        }

        boolean releaseByTransaction = false;
        try {
            // Recheck after obtaining the distributed lock. This handles the
            // case where another application instance completed the start first.
            ExamAttemptEntity existing = attempts.selectByExamAndUser(examId, userId);
            if (existing != null) {
                return detail(existing);
            }

            ExamAdmissionRow admission = exams.selectAdmissionForShare(examId, userId);
            if (admission == null) {
                throw new BusinessException("考试不存在");
            }
            if (admission.getCandidateStatus() == null || admission.getCandidateStatus() != 1) {
                throw new BusinessException(403, "考生账号不可用，无法参加考试");
            }
            ExamEntity exam = admission;

            LocalDateTime now = LocalDateTime.now();
            long nowEpoch = now.atZone(BUSINESS_ZONE).toEpochSecond();
            long startEpoch = exam.getStartTime().atZone(BUSINESS_ZONE).toEpochSecond();
            long endEpoch = exam.getEndTime().atZone(BUSINESS_ZONE).toEpochSecond();
            long admissionTtl = admissionTtlSeconds(now, exam.getEndTime());

            String admissionKey = "exam:admission:" + examId + ":" + userId;
            String admissionToken = UUID.randomUUID().toString();

            // The Redisson lock proves there is no active creator for this
            // exam/user pair. The Lua script atomically replaces an orphaned
            // marker and installs this request's token in one Redis round trip.
            Long admissionResult = redis.execute(
                    ADMIT_EXAM,
                    List.of(admissionKey),
                    exam.getStatus(),
                    String.valueOf(nowEpoch),
                    String.valueOf(startEpoch),
                    String.valueOf(endEpoch),
                    String.valueOf(admission.getCandidateStatus()),
                    admissionToken,
                    String.valueOf(admissionTtl)
            );

            if (admissionResult == null || admissionResult != 1L) {
                if (admissionResult != null && admissionResult == -1L) {
                    throw new BusinessException("考试不存在或尚未发布");
                }
                if (admissionResult != null && admissionResult == -2L) {
                    throw new BusinessException("考试尚未开始");
                }
                if (admissionResult != null && admissionResult == -3L) {
                    throw new BusinessException("考试时间已结束");
                }
                if (admissionResult != null && admissionResult == -4L) {
                    throw new BusinessException(403, "考生账号不可用，无法参加考试");
                }
                throw new BusinessException(409, "考试准入校验未通过，请刷新后重试");
            }

            AtomicReference<Long> createdAttemptId = new AtomicReference<>();
            registerStartSynchronization(lock, admissionKey, admissionToken, admissionTtl, createdAttemptId);
            releaseByTransaction = true;

            // Fetch paper links and question-bank rows with one JOIN. The former
            // implementation issued one additional SELECT for every question.
            List<SnapshotQuestion> snapshot = new ArrayList<>();
            for (ExamQuestionDetailRow question : links.selectQuestionDetailsByExamId(examId)) {
                List<String> options = json.readValue(
                        question.getOptionsJson() == null ? "[]" : question.getOptionsJson(),
                        new TypeReference<List<String>>() {
                        }
                );
                snapshot.add(new SnapshotQuestion(
                        question.getQuestionId(),
                        question.getType(),
                        question.getContent(),
                        options,
                        question.getCorrectAnswer(),
                        question.getScore(),
                        question.getAnalysis()
                ));
            }

            if (snapshot.isEmpty()) {
                throw new BusinessException("试卷没有可用题目");
            }

            LocalDateTime deadline = now.plusMinutes(exam.getDurationMinutes());
            if (deadline.isAfter(exam.getEndTime())) {
                deadline = exam.getEndTime();
            }

            ExamAttemptEntity attempt = new ExamAttemptEntity();
            attempt.setExamId(examId);
            attempt.setUserId(userId);
            attempt.setStatus("IN_PROGRESS");
            attempt.setStartedAt(now);
            attempt.setDeadlineAt(deadline);
            attempt.setQuestionSnapshot(json.writeValueAsString(snapshot));
            attempt.setVersion(0);
            attempt.setCreateTime(now);
            attempt.setUpdateTime(now);
            attempts.insert(attempt);

            OutboxEventEntity timeoutEvent = new OutboxEventEntity();
            timeoutEvent.setEventKey("TIMEOUT:" + attempt.getId());
            timeoutEvent.setEventType("TIMEOUT");
            timeoutEvent.setPayload(json.writeValueAsString(Map.of(
                    "type", "TIMEOUT",
                    "attemptId", attempt.getId(),
                    "eventKey", "TIMEOUT:" + attempt.getId()
            )));
            timeoutEvent.setStatus("PENDING");
            timeoutEvent.setRetryCount(0);
            timeoutEvent.setDeliverAt(deadline);
            timeoutEvent.setNextRetryAt(now);
            timeoutEvent.setCreateTime(now);
            timeoutEvent.setUpdateTime(now);
            outbox.insert(timeoutEvent);
            createdAttemptId.set(attempt.getId());

            // We already have the exam title and snapshot; avoid re-reading the
            // exam and the (still empty) answer table just to build the response.
            return detail(attempt, exam.getTitle(), snapshot, Map.of(), Map.of());
        } catch (BusinessException e) {
            throw e;
        } catch (Exception e) {
            throw new BusinessException("创建考试记录失败：" + e.getMessage());
        } finally {
            // Existing attempts and pre-admission failures do not register a
            // transaction callback, so release the lock immediately in those paths.
            if (!releaseByTransaction) {
                safeUnlock(lock);
            }
        }
    }

    private void registerStartSynchronization(
            RLock lock,
            String admissionKey,
            String admissionToken,
            long ttlSeconds,
            AtomicReference<Long> createdAttemptId) {

        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                Long attemptId = createdAttemptId.get();
                if (attemptId == null) {
                    return;
                }

                try {
                    redis.execute(
                            FINALIZE_ADMISSION,
                            List.of(admissionKey),
                            admissionToken,
                            String.valueOf(attemptId),
                            String.valueOf(ttlSeconds)
                    );
                } catch (Exception ignored) {
                    // The marker has a TTL and MySQL remains authoritative.
                }

                try {
                    redis.opsForValue().set(
                            "exam:attempt:" + attemptId,
                            "IN_PROGRESS",
                            ttlSeconds,
                            TimeUnit.SECONDS
                    );
                } catch (Exception ignored) {
                    // Redis is a cache; a failed cache write must not undo the committed attempt.
                }
            }

            @Override
            public void afterCompletion(int status) {
                try {
                    if (status != STATUS_COMMITTED) {
                        redis.execute(RELEASE_ADMISSION, List.of(admissionKey), admissionToken);
                    }
                } catch (Exception ignored) {
                    // Compare-token deletion and TTL prevent a stale marker from blocking forever.
                } finally {
                    safeUnlock(lock);
                }
            }
        });
    }

    private void safeUnlock(RLock lock) {
        try {
            if (lock.isHeldByCurrentThread()) {
                lock.unlock();
            }
        } catch (Exception ignored) {
            // Redisson Watchdog releases an abandoned lock after client failure.
        }
    }

    private long admissionTtlSeconds(LocalDateTime now, LocalDateTime examEndTime) {
        long seconds = Duration.between(now, examEndTime).toSeconds() + TimeUnit.DAYS.toSeconds(1);
        return Math.min(Integer.MAX_VALUE, Math.max(60L, seconds));
    }

    private long answerCacheTtlSeconds(LocalDateTime deadlineAt) {
        long seconds = Duration.between(LocalDateTime.now(), deadlineAt).toSeconds()
                + TimeUnit.DAYS.toSeconds(1);
        return Math.min(Integer.MAX_VALUE, Math.max(60L, seconds));
    }

    @Transactional
    public AttemptView get(Long attemptId, Long userId) {
        ExamAttemptEntity attempt = attempts.selectByIdForUpdate(attemptId);
        if (attempt == null) {
            throw new BusinessException("考试记录不存在");
        }
        if (!Objects.equals(attempt.getUserId(), userId)) {
            throw new BusinessException(403, "无权查看该考试记录");
        }
        if ("IN_PROGRESS".equals(attempt.getStatus())
                && !LocalDateTime.now().isBefore(attempt.getDeadlineAt())) {
            submitInternal(attempt);
            attempt = attempts.selectById(attemptId);
        }
        return detail(attempt);
    }

    public AttemptView getForGrading(Long attemptId) {
        return detail(require(attemptId));
    }

    @Transactional
    public SaveAnswerOutcome saveAnswer(Long attemptId, Long userId, SaveAnswerRequest request) {
        ExamAttemptEntity attempt = attempts.selectByIdForUpdate(attemptId);
        if (attempt == null) {
            throw new BusinessException("考试记录不存在");
        }
        if (!Objects.equals(attempt.getUserId(), userId)) {
            throw new BusinessException(403, "无权修改该答题记录");
        }
        if (!"IN_PROGRESS".equals(attempt.getStatus())) {
            throw new BusinessException("考试已交卷，不能继续答题");
        }
        if (!LocalDateTime.now().isBefore(attempt.getDeadlineAt())) {
            submitInternal(attempt);
            return new SaveAnswerOutcome(null, true);
        }

        snapshot(attempt).stream()
                .filter(question -> Objects.equals(question.questionId(), request.questionId()))
                .findFirst()
                .orElseThrow(() -> new BusinessException("题目不属于当前试卷"));

        if (request.version() == null || request.version() < 0) {
            throw new BusinessException(400, "答案版本号无效，请刷新试卷后重试");
        }

        String answer = request.answer() == null ? "" : request.answer().trim();
        // Ensure compatibility with older attempts that may not yet have an
        // answer row for this question. INSERT IGNORE is a no-op for existing rows.
        answers.insertIfAbsent(attemptId, request.questionId());

        // The attempt row is already locked above, which serializes answer saves
        // against submission. The version predicate is the final optimistic-lock
        // fence; no answer-row SELECT FOR UPDATE or read-after-write is needed.
        if (answers.updateAnswerByVersion(
                attemptId, request.questionId(), answer, request.version()) != 1) {
            throw new BusinessException(409, "答案已被更新，请刷新后重新保存");
        }

        int newVersion = request.version() + 1;
        String cacheKey = "exam:answers:" + attemptId;
        String questionField = String.valueOf(request.questionId());
        String cacheValue = encodeCacheEntry(newVersion, answer);
        long ttlSeconds = answerCacheTtlSeconds(attempt.getDeadlineAt());

        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                try {
                    redis.execute(
                            CACHE_ANSWER,
                            List.of(cacheKey),
                            questionField,
                            String.valueOf(newVersion),
                            cacheValue,
                            String.valueOf(ttlSeconds)
                    );
                } catch (Exception ignored) {
                    // A cache failure does not invalidate the committed DB answer.
                    // Reads compare cache version with DB version and fall back to DB.
                }
            }
        });

        return new SaveAnswerOutcome(
                new SaveAnswerResponse(
                        request.questionId(),
                        answer,
                        newVersion,
                        LocalDateTime.now()
                ),
                false
        );
    }

    private String encodeCacheEntry(Integer version, String answer) {
        String encoded = Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(answer.getBytes(StandardCharsets.UTF_8));
        return version + "|" + encoded;
    }

    private CachedAnswer decodeCacheEntry(Object raw) {
        if (raw == null) {
            return null;
        }
        try {
            String value = raw.toString();
            int separator = value.indexOf('|');
            if (separator <= 0) {
                return null;
            }
            int version = Integer.parseInt(value.substring(0, separator));
            String encoded = value.substring(separator + 1);
            String answer = new String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8);
            return new CachedAnswer(version, answer);
        } catch (Exception ignored) {
            return null;
        }
    }

    @Transactional
    public void submit(Long attemptId, Long userId) {
        ExamAttemptEntity attempt = attempts.selectByIdForUpdate(attemptId);
        if (attempt == null) {
            throw new BusinessException("考试记录不存在");
        }
        if (!Objects.equals(attempt.getUserId(), userId)) {
            throw new BusinessException(403, "无权提交该考试");
        }
        submitInternal(attempt);
    }

    @Transactional
    public boolean autoSubmit(Long attemptId) {
        ExamAttemptEntity attempt = attempts.selectByIdForUpdate(attemptId);
        if (attempt == null || !"IN_PROGRESS".equals(attempt.getStatus())) {
            return true;
        }
        if (LocalDateTime.now().isBefore(attempt.getDeadlineAt())) {
            return false;
        }
        submitInternal(attempt);
        return true;
    }

    private void submitInternal(ExamAttemptEntity attempt) {
        if (attempts.markSubmitted(attempt.getId()) == 0) {
            return;
        }

        LocalDateTime now = LocalDateTime.now();
        OutboxEventEntity event = new OutboxEventEntity();
        event.setEventKey("GRADE:" + attempt.getId());
        event.setEventType("GRADE");
        try {
            event.setPayload(json.writeValueAsString(Map.of(
                    "type", "GRADE",
                    "attemptId", attempt.getId(),
                    "eventKey", "GRADE:" + attempt.getId()
            )));
        } catch (Exception e) {
            throw new BusinessException("生成阅卷事件失败");
        }
        event.setStatus("PENDING");
        event.setRetryCount(0);
        event.setNextRetryAt(now);
        event.setCreateTime(now);
        event.setUpdateTime(now);
        outbox.insert(event);

        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                try {
                    redis.opsForValue().set(
                            "exam:attempt:" + attempt.getId(),
                            "SUBMITTED",
                            1,
                            TimeUnit.DAYS
                    );
                } catch (Exception ignored) {
                    // Database status and Outbox event remain authoritative.
                }
            }
        });
    }

    public List<ResultView> myResults(Long userId) {
        return grades.selectByUser(userId).stream().map(this::resultView).toList();
    }

    public ResultView result(Long attemptId, Long userId) {
        GradeResultEntity grade = grades.selectByAttemptId(attemptId);
        if (grade == null) {
            throw new BusinessException("成绩尚未生成");
        }
        if (!Objects.equals(grade.getUserId(), userId)) {
            throw new BusinessException(403, "无权查看该成绩");
        }
        return resultView(grade);
    }

    public List<GradeResultEntity> pendingGrades() {
        return grades.selectPendingManual();
    }

    public GradingDetail gradingDetail(Long attemptId) {
        ExamAttemptEntity attempt = require(attemptId);
        UserEntity user = users.selectById(attempt.getUserId());
        GradeResultEntity grade = grades.selectByAttemptId(attemptId);
        return new GradingDetail(
                detail(attempt),
                user == null ? "未知考生" : user.getDisplayName(),
                grade == null ? BigDecimal.ZERO : grade.getObjectiveScore(),
                grade == null ? BigDecimal.ZERO : grade.getSubjectiveScore(),
                grade == null ? "WAITING" : grade.getStatus()
        );
    }

    private ResultView resultView(GradeResultEntity grade) {
        ExamEntity exam = exams.selectById(grade.getExamId());
        UserEntity user = users.selectById(grade.getUserId());
        return new ResultView(
                grade.getAttemptId(),
                grade.getExamId(),
                exam == null ? "" : exam.getTitle(),
                user == null ? "" : user.getDisplayName(),
                grade.getObjectiveScore(),
                grade.getSubjectiveScore(),
                grade.getTotalScore(),
                grade.getStatus(),
                grade.getGradedAt()
        );
    }

    public ExamAttemptEntity require(Long id) {
        ExamAttemptEntity attempt = attempts.selectById(id);
        if (attempt == null) {
            throw new BusinessException("考试记录不存在");
        }
        return attempt;
    }

    public List<SnapshotQuestion> snapshot(ExamAttemptEntity attempt) {
        try {
            return json.readValue(
                    attempt.getQuestionSnapshot(),
                    new TypeReference<List<SnapshotQuestion>>() {
                    }
            );
        } catch (Exception e) {
            throw new BusinessException("试卷快照解析失败");
        }
    }

    /**
     * DB answer/version is authoritative. A cached answer is used only when
     * its version exactly matches the persisted row version.
     */
    private AttemptView detail(ExamAttemptEntity attempt) {
        ExamEntity exam = exams.selectById(attempt.getExamId());
        Map<Long, AnswerRecordEntity> answerMap = new HashMap<>();
        for (AnswerRecordEntity answer : answers.selectByAttempt(attempt.getId())) {
            answerMap.put(answer.getQuestionId(), answer);
        }

        Map<Object, Object> cachedEntries = Collections.emptyMap();
        if (!answerMap.isEmpty()) {
            try {
                // One HGETALL replaces one HGET per answered question. MySQL remains authoritative.
                cachedEntries = redis.opsForHash().entries("exam:answers:" + attempt.getId());
            } catch (Exception ignored) {
                // Redis is a cache only; always fall back to the persisted answers.
            }
        }

        return detail(
                attempt,
                exam == null ? "" : exam.getTitle(),
                snapshot(attempt),
                answerMap,
                cachedEntries
        );
    }

    private AttemptView detail(
            ExamAttemptEntity attempt,
            String examTitle,
            List<SnapshotQuestion> questions,
            Map<Long, AnswerRecordEntity> answerMap,
            Map<Object, Object> cachedEntries) {
        List<AttemptQuestionView> questionViews = new ArrayList<>();
        for (SnapshotQuestion question : questions) {
            AnswerRecordEntity persisted = answerMap.get(question.questionId());
            String answerText = persisted == null || persisted.getAnswer() == null
                    ? ""
                    : persisted.getAnswer();

            if (persisted != null) {
                Object cachedRaw = cachedEntries.get(String.valueOf(question.questionId()));
                CachedAnswer cached = decodeCacheEntry(cachedRaw);
                if (cached != null && Objects.equals(cached.version(), persisted.getVersion())) {
                    answerText = cached.answer();
                }
            }

            questionViews.add(new AttemptQuestionView(
                    question.questionId(),
                    question.type(),
                    question.content(),
                    question.options(),
                    question.score(),
                    answerText,
                    persisted == null ? 0 : persisted.getVersion()
            ));
        }

        return new AttemptView(
                attempt.getId(),
                attempt.getExamId(),
                examTitle,
                attempt.getStatus(),
                attempt.getStartedAt(),
                attempt.getDeadlineAt(),
                attempt.getSubmittedAt(),
                questionViews
        );
    }

    public record SaveAnswerOutcome(SaveAnswerResponse response, boolean submittedDueToTimeout) {
    }

    private record CachedAnswer(Integer version, String answer) {
    }

    public record SnapshotQuestion(
            Long questionId,
            String type,
            String content,
            List<String> options,
            String correctAnswer,
            BigDecimal score,
            String analysis
    ) {
    }
}
