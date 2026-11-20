package com.examforge.common;
import jakarta.validation.ConstraintViolationException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.*;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import java.util.stream.Collectors;
@RestControllerAdvice
public class GlobalExceptionHandler{
 @ExceptionHandler(BusinessException.class) public ResponseEntity<ApiResponse<Void>> business(BusinessException e){HttpStatus s=e.getCode()==401?HttpStatus.UNAUTHORIZED:e.getCode()==403?HttpStatus.FORBIDDEN:e.getCode()==409?HttpStatus.CONFLICT:HttpStatus.BAD_REQUEST;return ResponseEntity.status(s).body(ApiResponse.error(e.getCode(),e.getMessage()));}
 @ExceptionHandler(MethodArgumentNotValidException.class) public ResponseEntity<ApiResponse<Void>> validation(MethodArgumentNotValidException e){String m=e.getBindingResult().getFieldErrors().stream().map(x->x.getField()+": "+x.getDefaultMessage()).collect(Collectors.joining("; "));return ResponseEntity.badRequest().body(ApiResponse.error(400,m));}
 @ExceptionHandler({ConstraintViolationException.class,IllegalArgumentException.class}) public ResponseEntity<ApiResponse<Void>> invalid(Exception e){return ResponseEntity.badRequest().body(ApiResponse.error(400,e.getMessage()));}
 @ExceptionHandler(DuplicateKeyException.class) public ResponseEntity<ApiResponse<Void>> duplicate(Exception e){return ResponseEntity.status(409).body(ApiResponse.error(409,"记录已存在或请求重复，请刷新后重试"));}
 @ExceptionHandler(AccessDeniedException.class) public ResponseEntity<ApiResponse<Void>> denied(Exception e){return ResponseEntity.status(403).body(ApiResponse.error(403,"没有访问权限"));}
 @ExceptionHandler(Exception.class) public ResponseEntity<ApiResponse<Void>> other(Exception e){e.printStackTrace();return ResponseEntity.status(500).body(ApiResponse.error(500,"服务器内部错误："+e.getMessage()));}
}
