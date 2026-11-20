package com.examforge.mq.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.examforge.mq.entity.OutboxEventEntity;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.List;

@Mapper
public interface OutboxEventMapper extends BaseMapper<OutboxEventEntity> {

    @Select("""
            SELECT * FROM outbox_event
            WHERE status = 'PENDING'
              AND (next_retry_at IS NULL OR next_retry_at <= NOW())
            ORDER BY id ASC
            LIMIT #{limit}
            """)
    List<OutboxEventEntity> selectPending(@Param("limit") int limit);

    @Select("""
            SELECT * FROM outbox_event
            WHERE status = 'FAILED'
            ORDER BY update_time DESC, id DESC
            LIMIT #{limit}
            """)
    List<OutboxEventEntity> selectFailed(@Param("limit") int limit);

    @Update("""
            UPDATE outbox_event
            SET status = 'SENDING', update_time = NOW()
            WHERE id = #{id} AND status = 'PENDING'
            """)
    int claim(@Param("id") Long id);

    @Update("""
            UPDATE outbox_event
            SET status = 'SENT', published_at = NOW(), update_time = NOW(), last_error = NULL
            WHERE id = #{id} AND status = 'SENDING'
            """)
    int markSent(@Param("id") Long id);

    @Update("""
            UPDATE outbox_event
            SET retry_count = retry_count + 1,
                status = CASE WHEN retry_count + 1 >= 12 THEN 'FAILED' ELSE 'PENDING' END,
                next_retry_at = DATE_ADD(NOW(), INTERVAL LEAST(60, POW(2, retry_count + 1)) SECOND),
                last_error = #{error},
                update_time = NOW()
            WHERE id = #{id} AND status = 'SENDING'
            """)
    int markFailed(@Param("id") Long id, @Param("error") String error);

    @Update("""
            UPDATE outbox_event
            SET status = 'PENDING', next_retry_at = NOW(), update_time = NOW()
            WHERE status = 'SENDING'
              AND update_time < DATE_SUB(NOW(), INTERVAL 2 MINUTE)
            """)
    int recoverStuck();

    @Update("""
            UPDATE outbox_event
            SET status = 'PENDING',
                retry_count = 0,
                next_retry_at = NOW(),
                last_error = CONCAT('MANUAL_RETRY: ', LEFT(COALESCE(last_error, ''), 450)),
                update_time = NOW()
            WHERE id = #{id} AND status = 'FAILED'
            """)
    int retryFailed(@Param("id") Long id);
}
