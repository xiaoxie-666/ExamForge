package com.examforge.attempt;
import com.examforge.common.*;import com.examforge.common.ApiDtos.*;import com.examforge.exam.ExamService;import com.examforge.security.UserPrincipal;import jakarta.validation.Valid;import org.springframework.security.core.annotation.AuthenticationPrincipal;import org.springframework.web.bind.annotation.*;import java.util.List;
@RestController @RequestMapping("/api/candidate")public class CandidateController{
 private final ExamService exams;private final ExamAttemptService attempts;public CandidateController(ExamService e,ExamAttemptService a){exams=e;attempts=a;}
 @GetMapping("/exams")public ApiResponse<List<ExamView>>available(){return ApiResponse.ok(exams.listAvailable());}
 @PostMapping("/exams/{examId}/start")public ApiResponse<AttemptView>start(@PathVariable Long examId,@AuthenticationPrincipal UserPrincipal p){return ApiResponse.ok(attempts.start(examId,p.id()));}
 @GetMapping("/attempts/{attemptId}")public ApiResponse<AttemptView>detail(@PathVariable Long attemptId,@AuthenticationPrincipal UserPrincipal p){return ApiResponse.ok(attempts.get(attemptId,p.id()));}
 @PutMapping("/attempts/{attemptId}/answers")public ApiResponse<SaveAnswerResponse>save(@PathVariable Long attemptId,@Valid @RequestBody SaveAnswerRequest r,@AuthenticationPrincipal UserPrincipal p){ExamAttemptService.SaveAnswerOutcome outcome=attempts.saveAnswer(attemptId,p.id(),r);if(outcome.submittedDueToTimeout())throw new BusinessException(409,"考试时间已结束，系统已自动交卷");return ApiResponse.ok(outcome.response());}
 @PostMapping("/attempts/{attemptId}/submit")public ApiResponse<Void>submit(@PathVariable Long attemptId,@AuthenticationPrincipal UserPrincipal p){attempts.submit(attemptId,p.id());return ApiResponse.ok();}
 @GetMapping("/results")public ApiResponse<List<ResultView>>results(@AuthenticationPrincipal UserPrincipal p){return ApiResponse.ok(attempts.myResults(p.id()));}
 @GetMapping("/results/{attemptId}")public ApiResponse<ResultView>result(@PathVariable Long attemptId,@AuthenticationPrincipal UserPrincipal p){return ApiResponse.ok(attempts.result(attemptId,p.id()));}
}
