package com.examforge.security;
import com.examforge.user.entity.UserEntity;import io.jsonwebtoken.*;import io.jsonwebtoken.security.Keys;import org.springframework.beans.factory.annotation.Value;import org.springframework.stereotype.Component;import javax.crypto.SecretKey;import java.nio.charset.StandardCharsets;import java.time.Instant;import java.util.Date;
@Component public class JwtService{
 private final SecretKey key;private final long expireHours;
 public JwtService(@Value("${examforge.jwt.secret}")String secret,@Value("${examforge.jwt.expire-hours:12}")long expireHours){key=Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));this.expireHours=expireHours;}
 public String generate(UserEntity u){Instant now=Instant.now();return Jwts.builder().subject(u.getUsername()).claim("uid",u.getId()).claim("displayName",u.getDisplayName()).claim("role",u.getRole()).issuedAt(Date.from(now)).expiration(Date.from(now.plusSeconds(expireHours*3600))).signWith(key).compact();}
 public Claims parse(String token){return Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();}
}
