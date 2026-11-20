package com.examforge.user.entity;
import com.baomidou.mybatisplus.annotation.*;import lombok.*;import java.time.LocalDateTime;
@Data @NoArgsConstructor @TableName("sys_user") public class UserEntity{@TableId(type=IdType.AUTO)private Long id;private String username;private String password;private String displayName;private String role;private Integer status;private LocalDateTime createTime;private LocalDateTime updateTime;}
