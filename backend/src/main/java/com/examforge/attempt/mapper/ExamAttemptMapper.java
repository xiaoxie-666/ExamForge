package com.examforge.attempt.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.examforge.attempt.entity.ExamAttemptEntity;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDateTime;
import java.util.List;

@Mapper
public interface ExamAttemptMapper extends BaseMapper<ExamAttemptEntity> {

    @Select("SELECT * FROM exam_attempt WHERE exam_id=#{examId} AND user_id=#{userId} LIMIT 1")
    ExamAttemptEntity selectByExamAndUser(
            @Param("examId") Long examId,
            @Param("userId") Long userId
    );

    @Select("SELECT * FROM exam_attempt WHERE id=#{id} FOR UPDATE")
    ExamAttemptEntity selectByIdForUpdate(@Param("id") Long id);

    @Update("""
            UPDATE exam_attempt
            SET status='SUBMITTED',
                submitted_at=NOW(),
                version=version+1,
                update_time=NOW()
            WHERE id=#{id}
              AND status='IN_PROGRESS'
            """)
    int markSubmitted(@Param("id") Long id);

    @Select("""
            SELECT *
            FROM exam_attempt
            WHERE status='IN_PROGRESS'
              AND deadline_at<=#{now}
            ORDER BY deadline_at ASC
            LIMIT 500
            """)
    List<ExamAttemptEntity> selectExpired(@Param("now") LocalDateTime now);

    @Select("""
            SELECT a.*
            FROM exam_attempt a
            LEFT JOIN grade_result g ON g.attempt_id=a.id
            WHERE a.status='SUBMITTED'
              AND g.id IS NULL
            ORDER BY a.submitted_at ASC
            LIMIT 500
            """)
    List<ExamAttemptEntity> selectSubmittedWithoutGrade();
}
