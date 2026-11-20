package com.examforge.admin;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;import com.examforge.common.*;import com.examforge.common.ApiDtos.*;import com.examforge.grading.entity.GradeResultEntity;import com.examforge.grading.mapper.GradeResultMapper;import com.examforge.user.UserService;import com.examforge.user.mapper.UserMapper;import com.examforge.question.mapper.QuestionMapper;import com.examforge.exam.mapper.ExamMapper;import com.examforge.attempt.mapper.ExamAttemptMapper;import jakarta.validation.Valid;import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/admin") public class AdminController{
 private final UserService users;private final UserMapper um;private final QuestionMapper qm;private final ExamMapper em;private final ExamAttemptMapper am;private final GradeResultMapper gm;
 public AdminController(UserService u,UserMapper um,QuestionMapper qm,ExamMapper em,ExamAttemptMapper am,GradeResultMapper gm){users=u;this.um=um;this.qm=qm;this.em=em;this.am=am;this.gm=gm;}
 @GetMapping("/users")public ApiResponse<PageView<UserView>>users(@RequestParam(defaultValue="1")long page,@RequestParam(defaultValue="20")long size){return ApiResponse.ok(users.page(page,size));}
 @PostMapping("/users")public ApiResponse<UserView>create(@Valid @RequestBody CreateUserRequest r){return ApiResponse.ok(users.create(r));}
 @PutMapping("/users/{id}/status")public ApiResponse<Void>status(@PathVariable Long id,@RequestParam Integer status){if(status!=0&&status!=1)throw new BusinessException("status 仅支持 0 或 1");users.setStatus(id,status);return ApiResponse.ok();}
 @GetMapping("/dashboard")public ApiResponse<DashboardView>dashboard(){return ApiResponse.ok(new DashboardView(um.selectCount(null),qm.selectCount(null),em.selectCount(null),am.selectCount(null),gm.selectCount(new QueryWrapper<GradeResultEntity>().eq("status","PENDING_MANUAL"))));}
}
