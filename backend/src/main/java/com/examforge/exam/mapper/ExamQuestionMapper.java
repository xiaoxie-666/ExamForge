package com.examforge.exam.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.examforge.exam.entity.ExamQuestionEntity;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

@Mapper
public interface ExamQuestionMapper extends BaseMapper<ExamQuestionEntity> {

    @Select("SELECT * FROM exam_question WHERE exam_id=#{examId} ORDER BY sort_order ASC")
    List<ExamQuestionEntity> selectByExamId(@Param("examId") Long examId);

    /** Fetches all paper questions and their content with one JOIN instead of N+1 selects. */
    @Select("""
            SELECT q.id AS question_id,
                   q.type,
                   q.content,
                   q.options_json,
                   q.correct_answer,
                   q.analysis,
                   eq.score
            FROM exam_question eq
            INNER JOIN question_bank q ON q.id = eq.question_id
            WHERE eq.exam_id = #{examId}
            ORDER BY eq.sort_order ASC
            """)
    List<ExamQuestionDetailRow> selectQuestionDetailsByExamId(@Param("examId") Long examId);
}
