package com.examforge.admin;

import com.examforge.common.ApiResponse;
import com.examforge.common.BusinessException;
import com.examforge.mq.entity.OutboxEventEntity;
import com.examforge.mq.mapper.OutboxEventMapper;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;

@RestController
@RequestMapping("/api/admin/outbox")
public class OutboxAdminController {
    private final OutboxEventMapper outbox;

    public OutboxAdminController(OutboxEventMapper outbox) {
        this.outbox = outbox;
    }

    @GetMapping("/failed")
    public ApiResponse<List<FailedOutboxView>> failed(
            @RequestParam(defaultValue = "50") int limit) {
        int safeLimit = Math.max(1, Math.min(limit, 200));
        List<FailedOutboxView> result = outbox.selectFailed(safeLimit).stream()
                .map(OutboxAdminController::toView)
                .toList();
        return ApiResponse.ok(result);
    }

    @PostMapping("/{id}/retry")
    public ApiResponse<Void> retry(@PathVariable Long id) {
        if (outbox.retryFailed(id) != 1) {
            throw new BusinessException(409, "该 Outbox 事件不存在或当前状态不是 FAILED");
        }
        return ApiResponse.ok();
    }

    private static FailedOutboxView toView(OutboxEventEntity event) {
        return new FailedOutboxView(
                event.getId(),
                event.getEventKey(),
                event.getEventType(),
                event.getRetryCount(),
                event.getLastError(),
                event.getCreateTime(),
                event.getUpdateTime()
        );
    }

    public record FailedOutboxView(
            Long id,
            String eventKey,
            String eventType,
            Integer retryCount,
            String lastError,
            LocalDateTime createTime,
            LocalDateTime updateTime
    ) {}
}
