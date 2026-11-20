package com.examforge.user.mapper;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;import com.examforge.user.entity.UserEntity;import org.apache.ibatis.annotations.*;
@Mapper public interface UserMapper extends BaseMapper<UserEntity>{@Select("SELECT * FROM sys_user WHERE username=#{username} LIMIT 1")UserEntity selectByUsername(@Param("username")String username);}
