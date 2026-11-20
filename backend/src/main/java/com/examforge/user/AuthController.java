package com.examforge.user;
import com.examforge.common.*;import com.examforge.common.ApiDtos.*;import com.examforge.security.UserPrincipal;import com.examforge.user.entity.UserEntity;import com.examforge.user.mapper.UserMapper;import jakarta.validation.Valid;import org.springframework.security.core.annotation.AuthenticationPrincipal;import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/auth") public class AuthController{
 private final UserService users;private final UserMapper mapper;public AuthController(UserService u,UserMapper m){users=u;mapper=m;}
 @PostMapping("/login") public ApiResponse<LoginResponse>login(@Valid @RequestBody LoginRequest r){return ApiResponse.ok(users.login(r));}
 @GetMapping("/me") public ApiResponse<UserView>me(@AuthenticationPrincipal UserPrincipal p){UserEntity u=mapper.selectById(p.id());return ApiResponse.ok(new UserView(u.getId(),u.getUsername(),u.getDisplayName(),u.getRole(),u.getStatus(),u.getCreateTime()));}
}
