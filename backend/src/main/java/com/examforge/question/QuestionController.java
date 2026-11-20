package com.examforge.question;
import com.examforge.common.*;import com.examforge.common.ApiDtos.*;import com.examforge.security.UserPrincipal;import jakarta.validation.Valid;import org.springframework.http.*;import org.springframework.security.core.annotation.AuthenticationPrincipal;import org.springframework.web.bind.annotation.*;import org.springframework.web.multipart.MultipartFile;import java.io.IOException;
@RestController @RequestMapping("/api/questions")public class QuestionController{
 private final QuestionService service;public QuestionController(QuestionService s){service=s;}
 @GetMapping public ApiResponse<PageView<QuestionView>>page(@RequestParam(defaultValue="1")long page,@RequestParam(defaultValue="20")long size,@RequestParam(required=false)String keyword,@RequestParam(required=false)String type){return ApiResponse.ok(service.page(page,size,keyword,type));}
 @PostMapping public ApiResponse<QuestionView>create(@Valid @RequestBody QuestionRequest r,@AuthenticationPrincipal UserPrincipal p){return ApiResponse.ok(service.create(r,p.id()));}
 @PutMapping("/{id}")public ApiResponse<QuestionView>update(@PathVariable Long id,@Valid @RequestBody QuestionRequest r){return ApiResponse.ok(service.update(id,r));}
 @DeleteMapping("/{id}")public ApiResponse<Void>delete(@PathVariable Long id){service.delete(id);return ApiResponse.ok();}
 @PostMapping("/import")public ApiResponse<ImportResult>importExcel(@RequestParam("file")MultipartFile f,@AuthenticationPrincipal UserPrincipal p)throws IOException{return ApiResponse.ok(service.importExcel(f.getInputStream(),p.id()));}
 @GetMapping("/export")public ResponseEntity<byte[]>export()throws IOException{return ResponseEntity.ok().header(HttpHeaders.CONTENT_DISPOSITION,"attachment; filename=examforge-questions.xlsx").contentType(MediaType.APPLICATION_OCTET_STREAM).body(service.exportExcel());}
}
