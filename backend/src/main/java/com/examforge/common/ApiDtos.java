package com.examforge.common;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
public final class ApiDtos{
 private ApiDtos(){}
 public record LoginRequest(@NotBlank String username,@NotBlank String password){}
 public record LoginResponse(String token,Long userId,String username,String displayName,String role){}
 public record UserView(Long id,String username,String displayName,String role,Integer status,LocalDateTime createTime){}
 public record CreateUserRequest(@NotBlank String username,@NotBlank @Size(min=8,max=64) String password,@NotBlank String displayName,@NotBlank String role){}
 public record QuestionRequest(@NotBlank String type,@NotBlank String content,List<String> options,String correctAnswer,String analysis,String difficulty,String knowledgePoint,@NotNull @DecimalMin("0.1") BigDecimal defaultScore){}
 public record QuestionView(Long id,String type,String content,List<String> options,String correctAnswer,String analysis,String difficulty,String knowledgePoint,BigDecimal defaultScore){}
 public record CreateExamRequest(@NotBlank String title,String description,@NotNull LocalDateTime startTime,@NotNull LocalDateTime endTime,@NotNull @Min(1) @Max(600) Integer durationMinutes,@NotEmpty List<Long> questionIds){}
 public record ExamView(Long id,String title,String description,String status,LocalDateTime startTime,LocalDateTime endTime,Integer durationMinutes,Integer questionCount,LocalDateTime createTime){}
 public record AttemptQuestionView(Long questionId,String type,String content,List<String> options,BigDecimal score,String answer,Integer version){}
 public record AttemptView(Long attemptId,Long examId,String examTitle,String status,LocalDateTime startedAt,LocalDateTime deadlineAt,LocalDateTime submittedAt,List<AttemptQuestionView> questions){}
 public record SaveAnswerRequest(@NotNull Long questionId,String answer,@NotNull @Min(0) Integer version){}
 public record SaveAnswerResponse(Long questionId,String answer,Integer version,LocalDateTime savedAt){}
 public record SubjectiveScore(@NotNull Long questionId,@NotNull @DecimalMin("0.0") BigDecimal score,String comment){}
 public record ManualGradeRequest(@NotEmpty List<SubjectiveScore> scores){}
 public record ResultView(Long attemptId,Long examId,String examTitle,String studentName,BigDecimal objectiveScore,BigDecimal subjectiveScore,BigDecimal totalScore,String status,LocalDateTime gradedAt){}
 public record DashboardView(long users,long questions,long exams,long attempts,long pendingGrades){}
 public record ExamStatisticsSummary(
         Long examId,
         String examTitle,
         String examStatus,
         BigDecimal totalScore,
         long participants,
         long submitted,
         long graded,
         long pending,
         BigDecimal averageScore,
         BigDecimal highestScore,
         BigDecimal lowestScore,
         BigDecimal passRate
 ){}
 public record ScoreDistribution(String range,long count,BigDecimal rate){}
 public record ScoreRanking(
         long rank,
         Long attemptId,
         Long userId,
         String studentName,
         BigDecimal objectiveScore,
         BigDecimal subjectiveScore,
         BigDecimal totalScore,
         LocalDateTime gradedAt
 ){}
 public record ExamStatisticsDetail(
         ExamStatisticsSummary summary,
         List<ScoreDistribution> distribution,
         List<ScoreRanking> ranking
 ){}
 public record ImportResult(int imported,int skipped){}
 public record GradingDetail(AttemptView attempt,String studentName,BigDecimal objectiveScore,BigDecimal subjectiveScore,String gradeStatus){}
}
