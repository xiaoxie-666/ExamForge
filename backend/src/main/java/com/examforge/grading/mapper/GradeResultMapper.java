package com.examforge.grading.mapper;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;import com.examforge.grading.entity.GradeResultEntity;import org.apache.ibatis.annotations.*;import java.util.List;
@Mapper public interface GradeResultMapper extends BaseMapper<GradeResultEntity>{
 @Select("SELECT * FROM grade_result WHERE attempt_id=#{attemptId} LIMIT 1")GradeResultEntity selectByAttemptId(@Param("attemptId")Long attemptId);
 @Select("SELECT * FROM grade_result WHERE status='PENDING_MANUAL' ORDER BY id ASC")List<GradeResultEntity> selectPendingManual();
 @Select("SELECT * FROM grade_result WHERE user_id=#{userId} ORDER BY graded_at DESC,id DESC")List<GradeResultEntity> selectByUser(@Param("userId")Long userId);
}
