package com.examforge.security;
import io.jsonwebtoken.Claims;import jakarta.servlet.*;import jakarta.servlet.http.*;import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;import org.springframework.security.core.context.SecurityContextHolder;import org.springframework.stereotype.Component;import org.springframework.web.filter.OncePerRequestFilter;import java.io.IOException;
@Component public class JwtAuthenticationFilter extends OncePerRequestFilter{
 private final JwtService jwt;public JwtAuthenticationFilter(JwtService jwt){this.jwt=jwt;}
 @Override protected void doFilterInternal(HttpServletRequest req,HttpServletResponse res,FilterChain chain)throws ServletException,IOException{
  String h=req.getHeader("Authorization");if(h!=null&&h.startsWith("Bearer ")&&SecurityContextHolder.getContext().getAuthentication()==null){try{Claims c=jwt.parse(h.substring(7));Number uid=c.get("uid",Number.class);UserPrincipal p=new UserPrincipal(uid.longValue(),c.getSubject(),c.get("displayName",String.class),c.get("role",String.class));SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(p,null,p.getAuthorities()));}catch(Exception ignored){SecurityContextHolder.clearContext();}}
  chain.doFilter(req,res);
 }
}
