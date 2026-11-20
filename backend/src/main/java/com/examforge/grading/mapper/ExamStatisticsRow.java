package com.examforge.grading.mapper;

import lombok.Data;

import java.math.BigDecimal;

@Data
public class ExamStatisticsRow {
    private Long examId;
    private String examTitle;
    private String examStatus;
    private BigDecimal totalScore;
    private long participants;
    private long submitted;
    private long graded;
    private BigDecimal averageScore;
    private BigDecimal highestScore;
    private BigDecimal lowestScore;
}
