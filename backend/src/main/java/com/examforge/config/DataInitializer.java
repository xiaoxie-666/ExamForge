package com.examforge.config;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.examforge.exam.entity.ExamEntity;
import com.examforge.exam.entity.ExamQuestionEntity;
import com.examforge.exam.mapper.ExamMapper;
import com.examforge.exam.mapper.ExamQuestionMapper;
import com.examforge.question.entity.QuestionEntity;
import com.examforge.question.mapper.QuestionMapper;
import com.examforge.user.entity.UserEntity;
import com.examforge.user.mapper.UserMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Configuration
@Profile("api")
public class DataInitializer {
    private static final Logger log = LoggerFactory.getLogger(DataInitializer.class);

    @Bean
    CommandLineRunner seed(
            UserMapper users,
            QuestionMapper questions,
            ExamMapper exams,
            ExamQuestionMapper links,
            PasswordEncoder encoder,
            JdbcTemplate jdbc,
            @Value("${examforge.loadtest.enabled:false}") boolean loadtestEnabled,
            @Value("${examforge.loadtest.account-start:1001}") int loadtestAccountStart,
            @Value("${examforge.loadtest.account-count:1000}") int loadtestAccountCount,
            @Value("${examforge.loadtest.password}") String loadtestPassword) {

        return args -> {
            if (users.selectCount(null) == 0) {
                user(users, encoder, "admin", "Admin@123", "系统管理员", "ADMIN");
                user(users, encoder, "teacher", "Teacher@123", "示例教师", "TEACHER");
                user(users, encoder, "student", "Student@123", "示例考生", "STUDENT");
            }

            // Load-test users are opt-in and restricted to a dedicated account range.
            // Provisioning only inserts missing accounts; it never deletes or resets users.
            if (loadtestEnabled) {
                ensureLoadTestUsers(jdbc, encoder, loadtestAccountStart, loadtestAccountCount, loadtestPassword);
            }

            if (questions.selectCount(null) == 0) {
                String[][] data = {
                        {"SINGLE", "Java 中哪个关键字用于继承类？", "[\"A. implements\",\"B. extends\",\"C. import\",\"D. package\"]", "B"},
                        {"SINGLE", "下列哪种集合允许重复元素？", "[\"A. Set\",\"B. Map\",\"C. List\",\"D. TreeSet\"]", "C"},
                        {"MULTIPLE", "下列属于 Java 基本数据类型的有哪些？", "[\"A. int\",\"B. String\",\"C. boolean\",\"D. double\"]", "A,C,D"},
                        {"JUDGE", "Redis 是常见的内存型数据存储系统。", "[\"正确\",\"错误\"]", "正确"},
                        {"SINGLE", "MySQL InnoDB 默认支持哪种事务隔离级别？", "[\"A. READ UNCOMMITTED\",\"B. READ COMMITTED\",\"C. REPEATABLE READ\",\"D. SERIALIZABLE\"]", "C"},
                        {"SINGLE", "HTTP 状态码 401 通常表示什么？", "[\"A. 请求成功\",\"B. 未认证\",\"C. 服务器错误\",\"D. 资源不存在\"]", "B"},
                        {"JUDGE", "RocketMQ 可以用于业务异步解耦。", "[\"正确\",\"错误\"]", "正确"},
                        {"FILL", "Spring Boot 常用的配置文件格式包括 application.yml 和 application____。", "[]", "properties"},
                        {"SUBJECTIVE", "简述 Redis 缓存与 MySQL 持久化配合时需要关注的两个一致性问题。", "[]", ""},
                        {"SUBJECTIVE", "简述消息队列消费者幂等的常见实现方式。", "[]", ""}
                };

                for (String[] item : data) {
                    QuestionEntity question = new QuestionEntity();
                    question.setType(item[0]);
                    question.setContent(item[1]);
                    question.setOptionsJson(item[2]);
                    question.setCorrectAnswer(item[3]);
                    question.setAnalysis("示例题目解析：请结合对应知识点复习。");
                    question.setDifficulty("MEDIUM");
                    question.setKnowledgePoint("Java 后端基础");
                    question.setDefaultScore(new BigDecimal("SUBJECTIVE".equals(item[0]) ? "10" : "5"));
                    question.setCreatedBy(1L);
                    question.setCreateTime(LocalDateTime.now());
                    question.setUpdateTime(LocalDateTime.now());
                    questions.insert(question);
                }
            }

            if (exams.selectCount(null) == 0) {
                ExamEntity exam = new ExamEntity();
                exam.setTitle("Java 后端基础能力测评（演示）");
                exam.setDescription("初始化演示考试，包含客观题和主观题。");
                exam.setStatus("PUBLISHED");
                exam.setStartTime(LocalDateTime.now().minusMinutes(5));
                exam.setEndTime(LocalDateTime.now().plusDays(30));
                exam.setDurationMinutes(60);
                exam.setCreatedBy(1L);
                exam.setCreateTime(LocalDateTime.now());
                exam.setUpdateTime(LocalDateTime.now());
                exams.insert(exam);

                int order = 1;
                for (QuestionEntity question : questions.selectList(
                        new LambdaQueryWrapper<QuestionEntity>().orderByAsc(QuestionEntity::getId))) {
                    ExamQuestionEntity link = new ExamQuestionEntity();
                    link.setExamId(exam.getId());
                    link.setQuestionId(question.getId());
                    link.setSortOrder(order++);
                    link.setScore(question.getDefaultScore());
                    links.insert(link);
                }
            }
        };
    }

    private void ensureLoadTestUsers(
            JdbcTemplate jdbc,
            PasswordEncoder encoder,
            int requestedStart,
            int requestedCount,
            String loadtestPassword) {

        int start = Math.max(1, Math.min(requestedStart, 9000));
        int count = Math.max(0, Math.min(requestedCount, 10000));
        if (count == 0) {
            log.info("Load-test account provisioning is enabled but account-count is 0.");
            return;
        }
        if (start + count - 1 > 10000) {
            throw new IllegalArgumentException("Load-test account range must not exceed loadtest10000.");
        }

        Integer existing = jdbc.queryForObject(
                """
                SELECT COUNT(*)
                FROM sys_user
                WHERE username REGEXP '^loadtest[0-9]+$'
                  AND CAST(SUBSTRING(username, 9) AS UNSIGNED) BETWEEN ? AND ?
                """,
                Integer.class,
                start,
                start + count - 1
        );
        if (existing != null && existing == count) {
            log.info("Load-test accounts already available: range=loadtest{}..loadtest{}, count={}",
                    start, start + count - 1, existing);
            return;
        }

        // Hash once and reuse the same BCrypt hash for the dedicated local test accounts.
        String encodedPassword = encoder.encode(loadtestPassword);
        List<Object[]> batch = new ArrayList<>(count - (existing == null ? 0 : existing));
        LocalDateTime now = LocalDateTime.now();

        for (int i = start; i < start + count; i++) {
            String username = String.format("loadtest%04d", i);
            batch.add(new Object[]{
                    username,
                    encodedPassword,
                    "压测考生" + i,
                    "STUDENT",
                    1,
                    now,
                    now
            });
        }

        jdbc.batchUpdate(
                "INSERT IGNORE INTO sys_user " +
                        "(username,password,display_name,role,status,create_time,update_time) " +
                        "VALUES (?,?,?,?,?,?,?)",
                batch
        );

        Integer total = jdbc.queryForObject(
                """
                SELECT COUNT(*)
                FROM sys_user
                WHERE username REGEXP '^loadtest[0-9]+$'
                  AND CAST(SUBSTRING(username, 9) AS UNSIGNED) BETWEEN ? AND ?
                """,
                Integer.class,
                start,
                start + count - 1
        );
        if (total == null || total != count) {
            throw new IllegalStateException(
                    "Load-test account provisioning incomplete: range=" + start + "-" +
                            (start + count - 1) + ", actual=" + total + ", expected=" + count
            );
        }
        log.info("Load-test account provisioning completed: range=loadtest{}..loadtest{}, count={}",
                start, start + count - 1, total);
    }

    private void user(UserMapper mapper, PasswordEncoder encoder,
                      String username, String password, String displayName, String role) {
        UserEntity user = new UserEntity();
        user.setUsername(username);
        user.setPassword(encoder.encode(password));
        user.setDisplayName(displayName);
        user.setRole(role);
        user.setStatus(1);
        user.setCreateTime(LocalDateTime.now());
        user.setUpdateTime(LocalDateTime.now());
        mapper.insert(user);
    }
}
