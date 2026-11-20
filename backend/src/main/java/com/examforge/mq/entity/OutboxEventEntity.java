package com.examforge.mq.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.time.LocalDateTime;
@Data @NoArgsConstructor @TableName("outbox_event") public class OutboxEventEntity{@TableId(type=IdType.AUTO)private Long id;private String eventKey;private String eventType;private String payload;private String status;private Integer retryCount;private LocalDateTime deliverAt;private LocalDateTime nextRetryAt;private LocalDateTime publishedAt;private String lastError;private LocalDateTime createTime;private LocalDateTime updateTime;}
