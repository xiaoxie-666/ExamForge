package com.examforge.attempt.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.examforge.attempt.entity.AnswerRecordEntity;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.List;

@Mapper
public interface AnswerRecordMapper extends BaseMapper<AnswerRecordEntity> {

    @Insert("""
            INSERT IGNORE INTO answer_record
                (attempt_id, question_id, answer, version, create_time, update_time)
            VALUES (#{attemptId}, #{questionId}, '', 0, NOW(), NOW())
            """)
    int insertIfAbsent(@Param("attemptId") Long attemptId, @Param("questionId") Long questionId);

    @Select("SELECT * FROM answer_record WHERE attempt_id=#{attemptId} AND question_id=#{questionId} FOR UPDATE")
    AnswerRecordEntity selectForUpdate(@Param("attemptId") Long attemptId, @Param("questionId") Long questionId);

    @Update("""
            UPDATE answer_record
            SET answer = #{answer},
                version = version + 1,
                update_time = NOW()
            WHERE attempt_id = #{attemptId}
              AND question_id = #{questionId}
              AND version = #{version}
            """)
    int updateAnswerByVersion(
            @Param("attemptId") Long attemptId,
            @Param("questionId") Long questionId,
            @Param("answer") String answer,
            @Param("version") Integer version
    );


    @Select("SELECT * FROM answer_record WHERE attempt_id=#{attemptId}")
    List<AnswerRecordEntity> selectByAttempt(@Param("attemptId") Long attemptId);
}
