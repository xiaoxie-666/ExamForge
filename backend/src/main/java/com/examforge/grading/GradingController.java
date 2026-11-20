package com.examforge.grading;

import com.examforge.common.ApiDtos.*;
import com.examforge.common.ApiResponse;
import com.examforge.attempt.ExamAttemptService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/grading")
public class GradingController {

    private final ExamAttemptService attempts;
    private final GradingService grading;
    private final StatisticsService statistics;

    public GradingController(
            ExamAttemptService attempts,
            GradingService grading,
            StatisticsService statistics) {
        this.attempts = attempts;
        this.grading = grading;
        this.statistics = statistics;
    }

    @GetMapping("/pending")
    public ApiResponse<List<ResultView>> pending() {
        return ApiResponse.ok(attempts.pendingGrades().stream()
                .map(g -> new ResultView(
                        g.getAttemptId(),
                        g.getExamId(),
                        "",
                        "",
                        g.getObjectiveScore(),
                        g.getSubjectiveScore(),
                        g.getTotalScore(),
                        g.getStatus(),
                        g.getGradedAt()))
                .toList());
    }

    @GetMapping("/attempts/{attemptId}")
    public ApiResponse<GradingDetail> detail(@PathVariable Long attemptId) {
        return ApiResponse.ok(attempts.gradingDetail(attemptId));
    }

    @PostMapping("/attempts/{attemptId}/subjective")
    public ApiResponse<ResultView> grade(
            @PathVariable Long attemptId,
            @Valid @RequestBody ManualGradeRequest r) {
        return ApiResponse.ok(grading.manualGrade(attemptId, r));
    }

    @GetMapping("/statistics")
    public ApiResponse<List<ExamStatisticsSummary>> statistics() {
        return ApiResponse.ok(statistics.list());
    }

    @GetMapping("/statistics/{examId}")
    public ApiResponse<ExamStatisticsDetail> statisticsDetail(@PathVariable Long examId) {
        return ApiResponse.ok(statistics.detail(examId));
    }
}
