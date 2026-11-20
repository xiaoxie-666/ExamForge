package com.examforge.exam;
import com.examforge.common.*;import com.examforge.common.ApiDtos.*;import com.examforge.security.UserPrincipal;import jakarta.validation.Valid;import org.springframework.security.core.annotation.AuthenticationPrincipal;import org.springframework.web.bind.annotation.*;import java.util.List;
@RestController @RequestMapping("/api/exams")public class ExamController{
 private final ExamService service;public ExamController(ExamService s){service=s;}
 @GetMapping public ApiResponse<List<ExamView>>list(){return ApiResponse.ok(service.listManage());}
 @PostMapping public ApiResponse<ExamView>create(@Valid @RequestBody CreateExamRequest r,@AuthenticationPrincipal UserPrincipal p){return ApiResponse.ok(service.create(r,p.id()));}
 @PutMapping("/{id}/publish")public ApiResponse<Void>publish(@PathVariable Long id){service.publish(id);return ApiResponse.ok();}
 @PutMapping("/{id}/close")public ApiResponse<Void>close(@PathVariable Long id){service.close(id);return ApiResponse.ok();}
 @DeleteMapping("/{id}")public ApiResponse<Void>delete(@PathVariable Long id){service.delete(id);return ApiResponse.ok();}
}
