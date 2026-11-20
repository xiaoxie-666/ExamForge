package com.examforge.attempt.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.time.LocalDateTime;
@Data @NoArgsConstructor @TableName("exam_attempt") public class ExamAttemptEntity{@TableId(type=IdType.AUTO)private Long id;private Long examId;private Long userId;private String status;private LocalDateTime startedAt;private LocalDateTime deadlineAt;private LocalDateTime submittedAt;@TableField("question_snapshot")private String questionSnapshot;private Integer version;private LocalDateTime createTime;private LocalDateTime updateTime;}
