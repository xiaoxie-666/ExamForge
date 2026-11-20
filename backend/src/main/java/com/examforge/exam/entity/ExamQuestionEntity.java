package com.examforge.exam.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.math.BigDecimal;
@Data @NoArgsConstructor @TableName("exam_question") public class ExamQuestionEntity{@TableId(type=IdType.AUTO)private Long id;private Long examId;private Long questionId;private Integer sortOrder;private BigDecimal score;}
