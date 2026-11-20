
package com.examforge.mq;

import com.examforge.mq.entity.OutboxEventEntity;
import com.examforge.mq.mapper.OutboxEventMapper;
import org.apache.rocketmq.client.producer.SendResult;
import org.apache.rocketmq.client.producer.SendStatus;
import org.apache.rocketmq.common.message.MessageConst;
import org.apache.rocketmq.spring.core.RocketMQTemplate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.time.ZoneId;

@Component
@Profile("api")
public class OutboxPublisher {

    private static final Logger log =
            LoggerFactory.getLogger(OutboxPublisher.class);

    private final OutboxEventMapper mapper;
    private final RocketMQTemplate rocket;
    private final String topic;
    private final int batch;

    public OutboxPublisher(
            OutboxEventMapper mapper,
            RocketMQTemplate rocket,
            @Value("${examforge.rocketmq.topic}") String topic,
            @Value("${examforge.outbox.batch-size:50}") int batch) {

        this.mapper = mapper;
        this.rocket = rocket;
        this.topic = topic;
        this.batch = batch;
    }

    /**
     * 正常 Outbox 消息发布
     * 默认每 1 秒执行一次
     */
    @Scheduled(
            fixedDelayString =
                    "${examforge.outbox.publish-interval-ms:1000}"
    )
    public void publish() {

        for (OutboxEventEntity event : mapper.selectPending(batch)) {

            if (mapper.claim(event.getId()) != 1) {
                continue;
            }

            try {
                Message<String> message =
                        MessageBuilder.withPayload(event.getPayload())
                                .setHeader(
                                        MessageConst.PROPERTY_KEYS,
                                        event.getEventKey()
                                )
                                .build();

                SendResult result;

                boolean delayed =
                        "TIMEOUT".equals(event.getEventType())
                                && event.getDeliverAt() != null
                                && event.getDeliverAt()
                                .isAfter(LocalDateTime.now());

                if (delayed) {

                    long deliverAtMillis = event.getDeliverAt()
                            .atZone(ZoneId.systemDefault())
                            .toInstant()
                            .toEpochMilli();

                    result = rocket.syncSendDeliverTimeMills(
                            topic,
                            message,
                            deliverAtMillis
                    );

                } else {

                    result = rocket.syncSend(
                            topic,
                            message,
                            5000
                    );
                }

                if (result == null
                        || result.getSendStatus() != SendStatus.SEND_OK) {

                    throw new IllegalStateException(
                            "RocketMQ did not return SEND_OK: "
                                    + (result == null
                                    ? "null SendResult"
                                    : result.getSendStatus())
                    );
                }

                if (mapper.markSent(event.getId()) == 1) {

                    log.info(
                            "Outbox event published: eventId={}, eventKey={}, eventType={}, msgId={}, delayed={}",
                            event.getId(),
                            event.getEventKey(),
                            event.getEventType(),
                            result.getMsgId(),
                            delayed
                    );

                } else {

                    log.warn(
                            "RocketMQ accepted event but Outbox SENT update did not affect a row: eventId={}, eventKey={}, msgId={}",
                            event.getId(),
                            event.getEventKey(),
                            result.getMsgId()
                    );
                }

            } catch (Exception ex) {

                String error = ex.getMessage() == null
                        ? ex.getClass().getSimpleName()
                        : ex.getMessage();

                String safeError =
                        error.substring(0, Math.min(500, error.length()));

                int updated = mapper.markFailed(
                        event.getId(),
                        safeError
                );

                log.error(
                        "Outbox publish failed: eventId={}, eventKey={}, retryStateUpdated={}, error={}",
                        event.getId(),
                        event.getEventKey(),
                        updated == 1,
                        safeError,
                        ex
                );
            }
        }
    }

    /**
     * 异常 Outbox 事件恢复
     * 默认每 30 秒执行一次
     *
     * 仅恢复长期停留在 SENDING 状态的事件，
     * 不改变正常消息发布流程。
     */
    @Scheduled(
            fixedDelayString =
                    "${examforge.outbox.recovery-interval-ms:30000}"
    )
    public void recoverStuckEvents() {

        int recovered = mapper.recoverStuck();

        if (recovered > 0) {

            log.warn(
                    "Recovered {} stale Outbox events from SENDING to PENDING",
                    recovered
            );
        }
    }
}
