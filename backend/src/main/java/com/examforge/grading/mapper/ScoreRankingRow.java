package com.examforge.grading.mapper;

import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class ScoreRankingRow {
    private Long attemptId;
    private Long userId;
    private String studentName;
    private BigDecimal objectiveScore;
    private BigDecimal subjectiveScore;
    private BigDecimal totalScore;
    private LocalDateTime gradedAt;
}
