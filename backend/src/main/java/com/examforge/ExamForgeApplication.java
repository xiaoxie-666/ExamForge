package com.examforge;
import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
@SpringBootApplication
@MapperScan("com.examforge")
@EnableScheduling
public class ExamForgeApplication {
 public static void main(String[] args){SpringApplication.run(ExamForgeApplication.class,args);}
}
