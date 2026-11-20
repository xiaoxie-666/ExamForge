package com.examforge.job;
import com.examforge.attempt.ExamAttemptService;import com.examforge.attempt.mapper.ExamAttemptMapper;import com.examforge.grading.GradingService;import com.xxl.job.core.handler.annotation.XxlJob;import org.springframework.context.annotation.Profile;import org.springframework.stereotype.Component;import java.time.LocalDateTime;
@Component @Profile("worker")public class ExamTimeoutJob{
 private final ExamAttemptMapper mapper;private final ExamAttemptService attempts;private final GradingService grading;
 public ExamTimeoutJob(ExamAttemptMapper m,ExamAttemptService a,GradingService g){mapper=m;attempts=a;grading=g;}
 @XxlJob("scanTimeoutAttempts")public void scanTimeoutAttempts(){for(var a:mapper.selectExpired(LocalDateTime.now()))attempts.autoSubmit(a.getId());}
 @XxlJob("reconcileSubmittedAttempts")public void reconcileSubmittedAttempts(){for(var a:mapper.selectSubmittedWithoutGrade())grading.grade(a.getId());}
}
