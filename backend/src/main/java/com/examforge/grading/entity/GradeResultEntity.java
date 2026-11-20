package com.examforge.grading.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.math.BigDecimal;import java.time.LocalDateTime;
@Data @NoArgsConstructor @TableName("grade_result") public class GradeResultEntity{@TableId(type=IdType.AUTO)private Long id;private Long attemptId;private Long examId;private Long userId;private BigDecimal objectiveScore;private BigDecimal subjectiveScore;private BigDecimal totalScore;private String status;private LocalDateTime gradedAt;private LocalDateTime updateTime;}
