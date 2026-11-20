package com.examforge.exam;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.examforge.attempt.entity.ExamAttemptEntity;
import com.examforge.attempt.mapper.ExamAttemptMapper;
import com.examforge.common.ApiDtos.CreateExamRequest;
import com.examforge.common.ApiDtos.ExamView;
import com.examforge.common.BusinessException;
import com.examforge.exam.entity.ExamEntity;
import com.examforge.exam.entity.ExamQuestionEntity;
import com.examforge.exam.mapper.ExamMapper;
import com.examforge.exam.mapper.ExamQuestionMapper;
import com.examforge.question.entity.QuestionEntity;
import com.examforge.question.mapper.QuestionMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
public class ExamService {

    private final ExamMapper exams;
    private final ExamQuestionMapper links;
    private final QuestionMapper questions;
    private final ExamAttemptMapper attempts;

    public ExamService(
            ExamMapper exams,
            ExamQuestionMapper links,
            QuestionMapper questions,
            ExamAttemptMapper attempts) {
        this.exams = exams;
        this.links = links;
        this.questions = questions;
        this.attempts = attempts;
    }

    @Transactional
    public ExamView create(CreateExamRequest request, Long userId) {
        if (!request.endTime().isAfter(request.startTime())) {
            throw new BusinessException("考试结束时间必须晚于开始时间");
        }
        if (request.questionIds().stream().distinct().count() != request.questionIds().size()) {
            throw new BusinessException("试卷中存在重复题目");
        }

        ExamEntity exam = new ExamEntity();
        exam.setTitle(request.title());
        exam.setDescription(request.description());
        exam.setStatus("DRAFT");
        exam.setStartTime(request.startTime());
        exam.setEndTime(request.endTime());
        exam.setDurationMinutes(request.durationMinutes());
        exam.setCreatedBy(userId);
        exam.setCreateTime(LocalDateTime.now());
        exam.setUpdateTime(LocalDateTime.now());
        exams.insert(exam);

        int order = 1;
        for (Long questionId : request.questionIds()) {
            QuestionEntity question = questions.selectById(questionId);
            if (question == null) {
                throw new BusinessException("题目不存在：" + questionId);
            }
            ExamQuestionEntity link = new ExamQuestionEntity();
            link.setExamId(exam.getId());
            link.setQuestionId(questionId);
            link.setSortOrder(order++);
            link.setScore(question.getDefaultScore());
            links.insert(link);
        }
        return view(exam);
    }

    @Transactional
    public void publish(Long id) {
        ExamEntity exam = requireForUpdate(id);
        if (!"DRAFT".equals(exam.getStatus())) {
            throw new BusinessException("仅草稿考试可以发布");
        }
        if (links.selectByExamId(id).isEmpty()) {
            throw new BusinessException("试卷至少需要一道题目");
        }
        if (!exam.getEndTime().isAfter(LocalDateTime.now())) {
            throw new BusinessException("考试结束时间已过，无法发布");
        }

        exam.setStatus("PUBLISHED");
        exam.setUpdateTime(LocalDateTime.now());
        exams.updateById(exam);
    }

    @Transactional
    public void close(Long id) {
        ExamEntity exam = requireForUpdate(id);
        if ("CLOSED".equals(exam.getStatus())) {
            return;
        }
        if (!"PUBLISHED".equals(exam.getStatus())) {
            throw new BusinessException("仅已发布的考试可以关闭");
        }

        exam.setStatus("CLOSED");
        exam.setUpdateTime(LocalDateTime.now());
        exams.updateById(exam);
    }

    /**
     * An exam can be deleted only when it has no candidate attempts.
     * This keeps historical attempts/answers/grades auditable while still
     * allowing administrators to remove an unused DRAFT, PUBLISHED, or CLOSED exam.
     * The exam_question rows are removed by the existing ON DELETE CASCADE constraint.
     */
    @Transactional
    public void delete(Long id) {
        ExamEntity exam = requireForUpdate(id);

        Long attemptCount = attempts.selectCount(
                new LambdaQueryWrapper<ExamAttemptEntity>()
                        .eq(ExamAttemptEntity::getExamId, id)
        );
        if (attemptCount != null && attemptCount > 0) {
            throw new BusinessException(
                    "该考试已有考生参加记录，为保留答题和成绩历史，不允许删除"
            );
        }

        // No candidate has entered the exam, so deletion is safe even when
        // the exam is currently PUBLISHED. The row lock prevents a concurrent
        // close/start/delete operation from racing with this check.
        exams.deleteById(exam.getId());
    }

    public List<ExamView> listManage() {
        return exams.selectManageWithQuestionCount().stream().map(this::view).toList();
    }

    public List<ExamView> listAvailable() {
        return exams.selectAvailableWithQuestionCount(LocalDateTime.now())
                .stream().map(this::view).toList();
    }

    public ExamEntity require(Long id) {
        ExamEntity exam = exams.selectById(id);
        if (exam == null) {
            throw new BusinessException("考试不存在");
        }
        return exam;
    }

    private ExamEntity requireForUpdate(Long id) {
        ExamEntity exam = exams.selectByIdForUpdate(id);
        if (exam == null) {
            throw new BusinessException("考试不存在");
        }
        return exam;
    }

    public List<ExamQuestionEntity> questionLinks(Long id) {
        return links.selectByExamId(id);
    }

    private ExamView view(ExamEntity exam) {
        return new ExamView(
                exam.getId(),
                exam.getTitle(),
                exam.getDescription(),
                exam.getStatus(),
                exam.getStartTime(),
                exam.getEndTime(),
                exam.getDurationMinutes(),
                exam.getQuestionCount() != null
                        ? exam.getQuestionCount()
                        : links.selectByExamId(exam.getId()).size(),
                exam.getCreateTime()
        );
    }
}
