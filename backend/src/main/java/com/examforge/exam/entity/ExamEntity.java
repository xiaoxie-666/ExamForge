package com.examforge.exam.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.time.LocalDateTime;
@Data @NoArgsConstructor @TableName("exam") public class ExamEntity{@TableId(type=IdType.AUTO)private Long id;private String title;private String description;private String status;private LocalDateTime startTime;private LocalDateTime endTime;private Integer durationMinutes;private Long createdBy;private LocalDateTime createTime;private LocalDateTime updateTime;@TableField(exist=false)private Integer questionCount;}
