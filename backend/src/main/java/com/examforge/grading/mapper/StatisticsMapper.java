package com.examforge.grading.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Result;
import org.apache.ibatis.annotations.Results;
import org.apache.ibatis.annotations.Select;

import java.util.List;

@Mapper
public interface StatisticsMapper {

    @Select("""
            SELECT
                e.id AS exam_id,
                e.title AS exam_title,
                e.status AS exam_status,
                COALESCE((
                    SELECT SUM(eq.score)
                    FROM exam_question eq
                    WHERE eq.exam_id = e.id
                ), 0) AS total_score,
                COUNT(DISTINCT a.id) AS participants,
                COUNT(DISTINCT CASE WHEN a.status = 'SUBMITTED' THEN a.id END) AS submitted,
                COUNT(DISTINCT CASE WHEN g.status = 'COMPLETED' THEN g.id END) AS graded,
                COALESCE(AVG(CASE WHEN g.status = 'COMPLETED' THEN g.total_score END), 0) AS average_score,
                COALESCE(MAX(CASE WHEN g.status = 'COMPLETED' THEN g.total_score END), 0) AS highest_score,
                COALESCE(MIN(CASE WHEN g.status = 'COMPLETED' THEN g.total_score END), 0) AS lowest_score
            FROM exam e
            LEFT JOIN exam_attempt a ON a.exam_id = e.id
            LEFT JOIN grade_result g ON g.attempt_id = a.id
            GROUP BY e.id, e.title, e.status
            ORDER BY e.id DESC
            """)
    @Results(id = "examStatisticsRow", value = {
            @Result(column = "exam_id", property = "examId"),
            @Result(column = "exam_title", property = "examTitle"),
            @Result(column = "exam_status", property = "examStatus"),
            @Result(column = "total_score", property = "totalScore"),
            @Result(column = "participants", property = "participants"),
            @Result(column = "submitted", property = "submitted"),
            @Result(column = "graded", property = "graded"),
            @Result(column = "average_score", property = "averageScore"),
            @Result(column = "highest_score", property = "highestScore"),
            @Result(column = "lowest_score", property = "lowestScore")
    })
    List<ExamStatisticsRow> selectExamStatistics();

    @Select("""
            SELECT
                e.id AS exam_id,
                e.title AS exam_title,
                e.status AS exam_status,
                COALESCE((
                    SELECT SUM(eq.score)
                    FROM exam_question eq
                    WHERE eq.exam_id = e.id
                ), 0) AS total_score,
                COUNT(DISTINCT a.id) AS participants,
                COUNT(DISTINCT CASE WHEN a.status = 'SUBMITTED' THEN a.id END) AS submitted,
                COUNT(DISTINCT CASE WHEN g.status = 'COMPLETED' THEN g.id END) AS graded,
                COALESCE(AVG(CASE WHEN g.status = 'COMPLETED' THEN g.total_score END), 0) AS average_score,
                COALESCE(MAX(CASE WHEN g.status = 'COMPLETED' THEN g.total_score END), 0) AS highest_score,
                COALESCE(MIN(CASE WHEN g.status = 'COMPLETED' THEN g.total_score END), 0) AS lowest_score
            FROM exam e
            LEFT JOIN exam_attempt a ON a.exam_id = e.id
            LEFT JOIN grade_result g ON g.attempt_id = a.id
            WHERE e.id = #{examId}
            GROUP BY e.id, e.title, e.status
            """)
    @Results(id = "examStatisticsDetailRow", value = {
            @Result(column = "exam_id", property = "examId"),
            @Result(column = "exam_title", property = "examTitle"),
            @Result(column = "exam_status", property = "examStatus"),
            @Result(column = "total_score", property = "totalScore"),
            @Result(column = "participants", property = "participants"),
            @Result(column = "submitted", property = "submitted"),
            @Result(column = "graded", property = "graded"),
            @Result(column = "average_score", property = "averageScore"),
            @Result(column = "highest_score", property = "highestScore"),
            @Result(column = "lowest_score", property = "lowestScore")
    })
    ExamStatisticsRow selectExamStatisticsById(@Param("examId") Long examId);

    @Select("""
            SELECT
                g.attempt_id AS attempt_id,
                g.user_id AS user_id,
                COALESCE(u.display_name, u.username, '') AS student_name,
                g.objective_score AS objective_score,
                g.subjective_score AS subjective_score,
                g.total_score AS total_score,
                g.graded_at AS graded_at
            FROM grade_result g
            LEFT JOIN sys_user u ON u.id = g.user_id
            WHERE g.exam_id = #{examId}
              AND g.status = 'COMPLETED'
            ORDER BY g.total_score DESC, g.id ASC
            """)
    @Results(id = "scoreRankingRow", value = {
            @Result(column = "attempt_id", property = "attemptId"),
            @Result(column = "user_id", property = "userId"),
            @Result(column = "student_name", property = "studentName"),
            @Result(column = "objective_score", property = "objectiveScore"),
            @Result(column = "subjective_score", property = "subjectiveScore"),
            @Result(column = "total_score", property = "totalScore"),
            @Result(column = "graded_at", property = "gradedAt")
    })
    List<ScoreRankingRow> selectCompletedScores(@Param("examId") Long examId);
}
