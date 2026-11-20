# ExamForge｜高并发在线考试与测评平台

ExamForge 是一个面向高校及企业培训场景的前后端分离在线考试平台，覆盖题库管理、组卷与考试发布、在线答题、自动阅卷、人工评分和成绩统计，并提供 RocketMQ 异步事件处理、Outbox 可靠投递、超时交卷补偿及 JMeter 性能测试工程。

## 技术栈

- **后端：** Java 17、Spring Boot 3.3、Spring Security、JWT、MyBatis-Plus、Redisson
- **数据层：** MySQL 8、Redis 7
- **消息与任务：** RocketMQ 5.3、事务 Outbox、XXL-Job 3
- **前端：** Vue 3、TypeScript、Vite、Pinia、Element Plus、ECharts
- **测试与部署：** JMeter 5.6、Docker Compose

## 主要功能

### 管理端
- ADMIN / TEACHER / STUDENT 角色与权限控制
- 用户管理、题库 CRUD、Excel 导入导出
- 固定试卷组卷、考试发布与关闭、数据总览

### 考生端
- 可参加考试列表、考试准入、试卷快照
- 单选、多选、判断、填空及主观题
- 自动保存、答案版本控制、倒计时和主动交卷
- 成绩查询

### 异步处理与可靠性
- Redis 缓存、Lua 原子操作及 Redisson 分布式锁
- MySQL 事务、唯一约束、乐观锁和行级锁
- 事务 Outbox 与 RocketMQ 异步阅卷事件
- 消费幂等、消息重试及死信队列（DLQ）
- RocketMQ 延迟消息自动交卷、XXL-Job 超时扫描与补偿

## Docker Compose 快速启动

### 环境要求

- Docker Desktop 或 Docker Engine
- Docker Compose V2

### 1. 准备本地配置

在项目根目录执行：

```powershell
Copy-Item .env.example .env
```

编辑 `.env`，至少替换以下配置：

- `MYSQL_ROOT_PASSWORD`：MySQL root 密码
- `MYSQL_PASSWORD`：ExamForge 应用数据库用户密码
- `JWT_SECRET`：至少 32 个字符的随机密钥
- `XXL_JOB_TOKEN`：XXL-Job 通信 Token
- `LOADTEST_USER_PASSWORD`：本地压测账号密码（仅用于测试账号）

`.env` 是本地配置文件，已加入 `.gitignore`，不要提交到 GitHub。`.env.example` 只提供变量模板，不应填入真实密钥。

### 2. 启动服务

```powershell
docker compose config -q
docker compose up -d --build
docker compose ps
```

首次启动会构建 Java 和 Vue 镜像，并初始化 MySQL 数据库。MySQL 初始化 SQL 只会在空数据卷首次启动时执行；已有数据卷不会因为修改 SQL 文件而自动重建。等待 MySQL 状态变为 `healthy`，再检查 API：

```powershell
Invoke-RestMethod http://localhost:8080/actuator/health
docker compose logs --tail=100 api worker
```

### 3. 访问地址

| 服务 | 地址 |
|---|---|
| Web 前端 | http://localhost |
| API 健康检查 | http://localhost:8080/actuator/health |
| Swagger | http://localhost:8080/swagger-ui.html |
| XXL-Job 管理台 | http://localhost:8088/xxl-job-admin |

### 本地演示账号

首次初始化空数据库时会创建以下演示账号：

| 角色 | 用户名 | 初始密码 |
|---|---|---|
| 管理员 | `admin` | `Admin@123` |
| 教师 | `teacher` | `Teacher@123` |
| 考生 | `student` | `Student@123` |

XXL-Job 管理台默认账号为 `admin / 123456`。以上均为本地演示凭据，不可直接用于生产环境或公开部署；部署前应更换默认账号密码、数据库密码、JWT Secret 和 XXL-Job Token，并为服务配置访问控制。

## 服务说明

| Compose 服务 | 作用 |
|---|---|
| `web` | Nginx 托管 Vue 前端并反向代理 API |
| `api` | 登录、考试准入、答题、交卷和管理接口 |
| `worker` | RocketMQ 消费、异步阅卷和 XXL-Job 执行器 |
| `mysql` | 业务数据和 XXL-Job 数据存储 |
| `redis` | 缓存、分布式锁及开考控制 |
| `namesrv` | RocketMQ 路由发现 |
| `broker` | RocketMQ 消息存储与投递 |
| `xxl-admin` | XXL-Job 任务管理台 |

API 与 Worker 使用同一后端镜像，通过 Spring Profile 分开运行。Broker、NameServer 和 XXL-Job Admin 均为当前消息及任务链路所需组件，不是冗余容器。

## 1000 用户压测准备

普通演示环境默认不创建压测账号。需要进行压测时，在项目根目录执行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\prepare-test-environment.ps1 -ConfirmReset
```

该脚本会：

1. 检查本地 Docker Compose 环境并备份 ExamForge 数据库；
2. 停止 API / Worker，清理历史考试、答题、成绩和 Outbox 测试数据；
3. 保留题库与 `admin`、`teacher`、`student` 演示账号；
4. 准备演示考试和 1000 人专用客观题压测考试；
5. 仅在该次受控启动过程中启用 `loadtest1001` 至 `loadtest2000` 测试账号创建；
6. 保存新压测考试 ID 到本地忽略文件。

**警告：这是破坏性测试数据重置脚本。** 它会清理历史考试及除三个演示账号以外的用户。只允许在本地测试数据库运行；运行前确认 `.env` 指向本地 Compose 服务，并检查自动生成的数据库备份。不要执行 `docker compose down -v`。

## JMeter 性能测试

压测工程位于 `ExamForge_JMeter_Performance/`，使用非 GUI 模式运行。详细参数和执行方式见该目录的 [README](ExamForge_JMeter_Performance/README.md)。

主要测试计划：

- `entry`：登录及集中查询考试列表；
- `steady`：1000 个虚拟用户持续在线并周期性查询；
- `full`：登录、考试列表、分组开考、逐题保存、分组交卷、状态验证及异步阅卷数据库核验。

完整流程默认在 JMeter 请求完成后继续等待异步阅卷，数据库核验等待时间为 **1800 秒（30 分钟）**，避免将较慢的异步评分误判为永久失败。可通过 `-GradingWaitSeconds` 调整，最大 3600 秒。最终以 MySQL 中 1000 条成绩均为 `COMPLETED` 的核验结果为准。

JTL、HTML Dashboard、CSV 用户文件、运行日志和资源监控文件均在本地 `results/` 目录生成，不纳入 Git 仓库。当前测试记录和指标口径见 [性能测试摘要](docs/performance-test-summary.md)。

## 可靠性测试脚本

位于 `scripts/`：

- `test-outbox-recovery.ps1`：验证 Outbox 发布恢复和消费者幂等；
- `test-broker-outage-recovery.ps1`：验证 Broker 故障期间的事件恢复；
- `test-dlq.ps1`：使用隔离 Topic / Consumer Group 验证重试耗尽后的 DLQ 行为；
- `verify-test-environment.ps1`：只读检查测试账号、题库和考试准备状态。

这些脚本会从本地 `.env` 读取数据库和压测账号配置。执行具有写入或服务重启行为的测试前，先阅读脚本顶部参数和控制台提示。

## 本地开发（可选）

Docker Compose 是推荐启动方式。若希望在 IDE 中直接运行后端，需要自行启动 MySQL、Redis、RocketMQ NameServer / Broker 和 XXL-Job Admin，并在当前终端设置环境变量。Spring Boot 不会自动读取 Compose 的 `.env` 文件。

PowerShell 示例：

```powershell
$env:DB_URL = 'jdbc:mysql://localhost:3307/examforge?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai&useSSL=false&allowPublicKeyRetrieval=true'
$env:DB_USERNAME = 'examforge'
$env:DB_PASSWORD = '填写 .env 中的 MYSQL_PASSWORD'
$env:JWT_SECRET = '填写至少32字符的随机密钥'
$env:XXL_JOB_TOKEN = '填写 .env 中的 XXL_JOB_TOKEN'
$env:LOADTEST_USER_PASSWORD = '填写 .env 中的 LOADTEST_USER_PASSWORD'
$env:ROCKETMQ_NAME_SERVER = 'localhost:9876'
```

后端 API：

```powershell
cd backend
mvn spring-boot:run -Dspring-boot.run.profiles=api
```

另开终端运行 Worker：

```powershell
cd backend
mvn spring-boot:run -Dspring-boot.run.profiles=worker
```

前端：

```powershell
cd frontend
npm install
npm run dev
```

开发地址：http://localhost:5173。Vite 将 `/api` 请求代理到 `http://localhost:8080`。

## 数据一致性约束

- `uk_exam_user`：同一考生同一场考试只创建一条考试记录；
- `uk_attempt_question`：同一考试记录中的每道题只保留一条答案记录；
- `grade_result.attempt_id UNIQUE`：同一考试记录只生成一条成绩；
- `outbox_event.event_key UNIQUE`：防止重复创建相同业务事件；
- 答案保存使用考试记录行锁与 version 条件更新，协调答题保存和交卷竞争。

## 当前项目边界

- 当前为模块化单体，API 与 Worker 通过不同 Spring Profile 部署，不是完整微服务集群；
- 当前考试资格以已发布考试的开放时间和登录状态为基础，未实现班级 / 部门定向分配；
- 当前组卷为固定题目组卷，未实现知识点随机抽题；
- Excel 导入按项目导出模板列顺序读取；
- 当前不包含生产级多机房容灾、API 网关限流和分布式事务协调。

## License

本仓库尚未指定开源许可证。若计划允许他人复制、修改或商用，请在公开发布前选择并添加适合的 LICENSE 文件。
