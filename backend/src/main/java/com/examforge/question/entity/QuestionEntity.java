package com.examforge.question.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.math.BigDecimal;import java.time.LocalDateTime;
@Data @NoArgsConstructor @TableName("question_bank") public class QuestionEntity{@TableId(type=IdType.AUTO)private Long id;private String type;private String content;private String optionsJson;private String correctAnswer;private String analysis;private String difficulty;private String knowledgePoint;private BigDecimal defaultScore;private Long createdBy;private LocalDateTime createTime;private LocalDateTime updateTime;}
