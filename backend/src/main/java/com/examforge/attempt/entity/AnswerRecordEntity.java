package com.examforge.attempt.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.math.BigDecimal;import java.time.LocalDateTime;
@Data @NoArgsConstructor @TableName("answer_record") public class AnswerRecordEntity{@TableId(type=IdType.AUTO)private Long id;private Long attemptId;private Long questionId;private String answer;private Integer version;private BigDecimal score;private String teacherComment;private LocalDateTime createTime;private LocalDateTime updateTime;}
