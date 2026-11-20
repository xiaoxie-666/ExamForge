package com.examforge.exam.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.examforge.exam.entity.ExamEntity;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.time.LocalDateTime;
import java.util.List;

@Mapper
public interface ExamMapper extends BaseMapper<ExamEntity> {

    @Select("SELECT * FROM exam WHERE id = #{id} FOR UPDATE")
    ExamEntity selectByIdForUpdate(@Param("id") Long id);

    @Select("SELECT * FROM exam WHERE id = #{id} FOR SHARE")
    ExamEntity selectByIdForShare(@Param("id") Long id);

    /** Locks and reads the exam plus candidate status with one database round trip. */
    @Select("""
            SELECT e.*, u.status AS candidate_status
            FROM exam e
            LEFT JOIN sys_user u ON u.id = #{userId}
            WHERE e.id = #{examId}
            FOR SHARE
            """)
    ExamAdmissionRow selectAdmissionForShare(
            @Param("examId") Long examId,
            @Param("userId") Long userId
    );

    /** Returns management exams and question counts without an N+1 count query. */
    @Select("""
            SELECT e.*, COUNT(eq.id) AS question_count
            FROM exam e
            LEFT JOIN exam_question eq ON eq.exam_id = e.id
            GROUP BY e.id
            ORDER BY e.id DESC
            """)
    List<ExamEntity> selectManageWithQuestionCount();

    /** Returns currently available exams and question counts in one query. */
    @Select("""
            SELECT e.*, COUNT(eq.id) AS question_count
            FROM exam e
            LEFT JOIN exam_question eq ON eq.exam_id = e.id
            WHERE e.status = 'PUBLISHED'
              AND e.start_time <= #{now}
              AND e.end_time > #{now}
            GROUP BY e.id
            ORDER BY e.start_time ASC
            """)
    List<ExamEntity> selectAvailableWithQuestionCount(@Param("now") LocalDateTime now);
}
