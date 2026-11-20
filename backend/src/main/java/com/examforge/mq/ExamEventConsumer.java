package com.examforge.mq;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.examforge.attempt.ExamAttemptService;
import com.examforge.grading.GradingService;
import org.apache.rocketmq.spring.annotation.RocketMQMessageListener;
import org.apache.rocketmq.spring.core.RocketMQListener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("worker")
@RocketMQMessageListener(
        topic = "${examforge.rocketmq.topic}",
        consumerGroup = "${examforge.rocketmq.consumer-group}",
        maxReconsumeTimes = 16,
        consumeThreadNumber = 8,
        consumeThreadMax = 32
)
public class ExamEventConsumer implements RocketMQListener<String> {
    private static final Logger log = LoggerFactory.getLogger(ExamEventConsumer.class);

    private final ObjectMapper json;
    private final ExamAttemptService attempts;
    private final GradingService grading;

    public ExamEventConsumer(ObjectMapper json, ExamAttemptService attempts, GradingService grading) {
        this.json = json;
        this.attempts = attempts;
        this.grading = grading;
    }

    @Override
    public void onMessage(String message) {
        long startedAt = System.nanoTime();
        String eventKey = "unknown";
        String eventType = "unknown";
        Long attemptId = null;

        try {
            JsonNode node = json.readTree(message);
            attemptId = node.path("attemptId").asLong();
            eventType = node.path("type").asText();
            eventKey = node.path("eventKey").asText(eventType + ":" + attemptId);

            if (attemptId == null || attemptId <= 0 || eventType.isBlank()) {
                throw new IllegalArgumentException("Invalid exam event payload: " + message);
            }

            if ("TIMEOUT".equals(eventType)) {
                // A delayed message can be delivered slightly early due to clock differences.
                // Throwing keeps the message retryable instead of acknowledging it prematurely.
                if (!attempts.autoSubmit(attemptId)) {
                    throw new IllegalStateException("Timeout event arrived before the attempt deadline");
                }
            } else if ("GRADE".equals(eventType)) {
                // grade() is idempotent for sequential duplicates and protected by
                // the unique grade_result.attempt_id constraint for concurrent duplicates.
                grading.grade(attemptId);
            } else {
                throw new IllegalArgumentException("Unknown exam event type: " + eventType);
            }

            long elapsedMs = (System.nanoTime() - startedAt) / 1_000_000;
            log.info("Exam event consumed successfully: eventKey={}, type={}, attemptId={}, elapsedMs={}",
                    eventKey, eventType, attemptId, elapsedMs);
        } catch (Exception ex) {
            long elapsedMs = (System.nanoTime() - startedAt) / 1_000_000;
            log.error("Exam event consumption failed: eventKey={}, type={}, attemptId={}, elapsedMs={}, error={}",
                    eventKey, eventType, attemptId, elapsedMs, ex.getMessage(), ex);
            throw new IllegalStateException("Exam event processing failed: " + eventKey, ex);
        }
    }
}
