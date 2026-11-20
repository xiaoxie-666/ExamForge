
package com.examforge.config;

import com.examforge.security.JwtAuthenticationFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

@Configuration
public class SecurityConfig {

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            JwtAuthenticationFilter jwt
    ) throws Exception {

        http
            .csrf(csrf -> csrf.disable())

            .cors(cors ->
                cors.configurationSource(corsConfigurationSource())
            )

            .sessionManagement(session ->
                session.sessionCreationPolicy(
                    SessionCreationPolicy.STATELESS
                )
            )

            .authorizeHttpRequests(auth -> auth

                // 公开接口
                .requestMatchers(
                    "/api/auth/login",
                    "/actuator/health",
                    "/swagger-ui/**",
                    "/swagger-ui.html",
                    "/v3/api-docs/**"
                ).permitAll()

                // 管理员专属接口
                .requestMatchers("/api/admin/outbox/**")
                .hasRole("ADMIN")

                // 管理员和教师接口
                .requestMatchers(
                    "/api/admin/**",
                    "/api/questions/**",
                    "/api/exams/**"
                ).hasAnyRole("ADMIN", "TEACHER")

                .requestMatchers("/api/grading/**")
                .hasAnyRole("ADMIN", "TEACHER")

                // 学生接口
                .requestMatchers("/api/candidate/**")
                .hasRole("STUDENT")

                // 其他接口仍然需要认证
                .anyRequest().authenticated()
            )

            .addFilterBefore(
                jwt,
                UsernamePasswordAuthenticationFilter.class
            );

        return http.build();
    }

    /**
     * CORS 跨域配置
     */
    @Bean
    CorsConfigurationSource corsConfigurationSource() {

        CorsConfiguration config = new CorsConfiguration();

        // 本地开发环境 + Docker 部署环境
        config.setAllowedOrigins(List.of(
            "http://localhost:5173",
            "http://127.0.0.1:5173",
            "http://localhost:18000",
            "http://127.0.0.1:18000"
        ));

        config.setAllowedMethods(List.of(
            "GET",
            "POST",
            "PUT",
            "DELETE",
            "OPTIONS"
        ));

        config.setAllowedHeaders(List.of("*"));

        config.setAllowCredentials(true);

        config.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source =
            new UrlBasedCorsConfigurationSource();

        source.registerCorsConfiguration("/**", config);

        return source;
    }
}
