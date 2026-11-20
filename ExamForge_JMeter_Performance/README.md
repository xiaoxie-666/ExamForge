# ExamForge JMeter 压测工程（1000 用户全链路版）

本目录是唯一需要维护的 JMeter 压测工程，独立于 Java/Vue 源码。JMeter 安装目录不需要复制进本项目。

## 1. 目录结构

```text
ExamForge_JMeter_Performance/
├─ run-loadtest.ps1          # 统一入口：entry / steady / full
├─ verify-full-run.ps1       # 等待 RocketMQ 阅卷完成，并核对 MySQL 最终结果
├─ summarize-results.ps1     # 自动统计请求数、错误率、TPS、P90/P95/P99
├─ monitor-docker.ps1        # 可选：采集 API/Worker/MySQL/Redis/RocketMQ 资源
├─ README.md
├─ config/
│  └─ exam-id.txt            # 由主项目的准备脚本自动生成
└─ jmeter/
   ├─ exam-entry.jmx         # 登录 + 集中查询考试列表（只读）
   ├─ exam-steady.jmx        # 持续在线会话（只读）
   ├─ submit-flow.jmx        # 开考、逐题保存、交卷、状态验证
   ├─ generate_users_csv.py # 可选 CSV 生成器
   └─ post-run-check.sql    # 手动数据库核验
```

`users.csv` 会在每次运行时自动生成；JTL、JMeter 日志、HTML Dashboard 和统计文件写入独立的 `results/<run-name>/` 目录。`results/`、`jmeter/users.csv` 不随压测工程分发；运行时会自动创建。

## 2. 环境要求

- Windows PowerShell 5.1 或 PowerShell 7。
- Java 17。
- Apache JMeter 5.6.x，建议 5.6.3。
- ExamForge Docker Compose 服务已启动，API 健康检查为 `UP`。
- 默认 API 地址：`http://127.0.0.1:8080`。

> **Compose 环境说明：** 本目录中的压测辅助脚本默认使用仓库标准 `docker-compose.yml`（API 端口 8080，容器名 `examforge-api` / `examforge-worker`）。当前开发机的隔离环境 `docker-compose.isolated.yml` 使用 API 端口 18080、前端端口 18000，容器名为 `examforge-clean-*`。隔离配置仅用于本机复用现有 Docker 数据卷，并在 `.gitignore` 中排除；不要把两套 Compose 配置混用。若要运行本目录的全链路压测脚本，请使用标准 Compose 环境，或先同步调整脚本中的 Compose 项目参数、容器名和 API 端口。
- 测试账号：`loadtest1001` 至 `loadtest2000`；密码从项目根目录 `.env` 的 `LOADTEST_USER_PASSWORD` 读取。

## 3. 首次准备测试数据（只需在重置测试环境时执行）

先在主项目根目录准备 `.env`（由 `.env.example` 复制并填写），再运行准备脚本。该脚本会：
1. 停止 API 和 Worker，避免清理期间仍有业务写入；
2. 备份 MySQL 到 `backups/`；
3. 只清理 ExamForge 的 Redis 缓存键和开考锁，不执行 `FLUSHDB`；
4. 删除历史考试、答题、成绩、Outbox 数据，以及除 `admin/teacher/student` 外的用户；
5. 保留现有题库，幂等新增 20 道客观题；
6. 创建一场包含主观题的功能演示考试，以及一场只含 10 道客观题的压测考试；
7. 仅在本次受控启动中临时开启压测账号创建，重建 API/Worker，自动补齐 `loadtest1001..loadtest2000`；
8. 将压测考试 ID 写入本地忽略文件 `config/exam-id.txt`，并在控制台打印演示考试 ID。

```powershell
# 按实际克隆目录修改此路径；当前工作目录示例为 D:\ready_github\ExamForge
$ProjectRoot = 'D:\ready_github\ExamForge'
Set-Location $ProjectRoot
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\prepare-test-environment.ps1 -ConfirmReset
```

**破坏性操作：** 此脚本会清空所有历史考试和考试记录，并删除除三个演示账号以外的用户。执行前会自动备份 MySQL。只在本地测试环境执行，绝不能连接生产库。不要使用 `docker compose down -v`。

JMeter `full` 计划只使用第二场客观题压测考试；第一场混合题型演示考试保留主观题，可用于小规模人工阅卷功能演示。 题库保留原有10道题并新增20道客观题，整理后共30道：单选14、多选6、判断7、填空1、主观2。压测专用试卷固定为6道单选、2道多选、2道判断，每题5分，共50分。 JMeter 使用固定模拟答案（选择题取首个选项，多选题取首个选项代码，判断题取首个选项），目的是压测答案写入和异步阅卷链路，不用于评估考生得分分布或阅卷准确率；评分正确性应通过功能测试单独验证。

旧 RocketMQ 延迟消息不会被清空。清理脚本不会重置 MySQL 自增 ID，因此旧消息引用的 attempt ID 不会与新记录复用；Worker 收到不存在的旧 attempt 时会按现有幂等逻辑忽略。

## 4. 推荐：一次 1000 用户完整考试链路测试

在准备脚本成功后，进入本目录：

```powershell
# 按实际克隆目录修改此路径；当前工作目录示例为 D:\ready_github\ExamForge
$ProjectRoot = 'D:\ready_github\ExamForge'
Set-Location (Join-Path $ProjectRoot 'ExamForge_JMeter_Performance')
Set-ExecutionPolicy -Scope Process Bypass

.\run-loadtest.ps1 `
  -Plan full `
  -Threads 1000 `
  -Ramp 300 `
  -AccountStart 1001 `
  -AccountCount 1000 `
  -StartGroupSize 50 `
  -SubmitGroupSize 50 `
  -AnswerThinkTimeMs 100 `
  -GradingWaitSeconds 1800 `
  -JMeterPath "D:\Tools\apache-jmeter-5.6.3\bin\jmeter.bat"
```

`-ExamId` 默认从 `config/exam-id.txt` 读取，不需要每次手工修改考试 ID。运行脚本会从项目根目录 `.env` 读取 MySQL 和压测账号配置。

### 这个测试实际模拟什么？

1. 1000 个独立虚拟用户在 300 秒内逐步启动，分别登录一次；
2. 登录成功后查询可参加考试；
3. 开考请求按每组 50 人释放，避免 1000 个开考请求在同一瞬间打到 API；
4. 成功开考的用户进入独立的全员屏障，等待所有 1000 个用户完成开考，然后同时进入答题阶段；
5. 每个用户逐题保存试卷中的 10 道题，目标为 10,000 次答案保存；
6. 答题完成后按每组 50 人释放交卷请求；
7. JMeter 校验考试状态为 `SUBMITTED`；
8. JMeter 结束后，`verify-full-run.ps1` 默认最多等待 1800 秒（30 分钟），持续轮询 RocketMQ Worker 的异步阅卷结果，并检查 1000 条 `COMPLETED` 成绩、答案记录和 GRADE Outbox 发送状态。可通过 `-GradingWaitSeconds` 调整等待时间，范围为 60–3600 秒。

**同步屏障必须有明确作用范围。** 全员开考屏障被放在专用控制器内部，只作用于答题阶段的内部屏障采样器，不会影响登录、考试列表或开考请求。这样 `Ramp=300` 才能真正把登录和列表请求分散到 300 秒内，而不是等1000个线程全部启动后瞬间发出。

内部屏障会在 JTL 中产生一条名为 `00 Barrier - all candidates started` 的非 HTTP 采样记录。`summary.csv/txt` 会将它单独统计，不计入 HTTP 请求数和 HTTP TPS。

### 分组参数

- `StartGroupSize=50`：每50个线程一组发起开考请求。
- `StartGroupSize=0`：所有线程同时发起开考请求，属于更激进的突发测试。
- `SubmitGroupSize=50`：每50个线程一组交卷。
- `SubmitGroupSize=0`：所有成功开考的用户同时交卷。
- `AnswerThinkTimeMs=100`：每道题保存之间等待100ms。设为0会形成更激进的答案写入突发。

兼容旧参数 `-SyncGroupSize`：如果显式传入，它会同时覆盖开考和交卷分组。新测试建议分别使用 `-StartGroupSize` 和 `-SubmitGroupSize`。

### 失败处理

完整链路采用 fail-fast：任意 HTTP 请求或断言失败，JMeter 就停止整个测试，避免登录失败后继续携带无效 JWT 请求考试列表，产生大量连锁 403，也避免部分线程退出后其他线程永久等待全员屏障。脚本仍会保留并汇总已产生的 JTL；只要出现 HTTP 错误、屏障样本数量不足或 JMeter 异常退出，就跳过异步阅卷最终核验。

**完整流程具有写入性。** 同一账号对同一场考试只能创建一次考试记录。脚本会在启动 JMeter 前查询数据库，如果账号范围已经参加过该考试，会拒绝运行。测试中途失败也可能已经创建部分考试记录；重新测试前必须核对数据库，必要时重新运行主项目准备脚本创建新考试，不要直接复用同一考试和账号范围。
## 5. 只读测试（可重复）

### A. entry：登录 + 集中查询

```powershell
.\run-loadtest.ps1 `
  -Plan entry `
  -Threads 1000 `
  -Ramp 120 `
  -AccountStart 1001 `
  -AccountCount 1000 `
  -JMeterPath "D:\Tools\apache-jmeter-5.6.3\bin\jmeter.bat"
```

默认所有用户登录后一起查询考试列表。该计划不创建考试记录，可重复运行。

### B. steady：持续在线会话

```powershell
.\run-loadtest.ps1 `
  -Plan steady `
  -Threads 1000 `
  -Ramp 120 `
  -HoldSeconds 120 `
  -ThinkTimeMs 5000 `
  -AccountStart 1001 `
  -AccountCount 1000 `
  -JMeterPath "D:\Tools\apache-jmeter-5.6.3\bin\jmeter.bat"
```

每个用户只登录一次，保持会话并周期性查询考试列表，不创建考试记录。总时长为 Ramp + HoldSeconds。

## 6. 资源监控

正式全链路测试时，建议另开 PowerShell 窗口：

```powershell
$ProjectRoot = 'D:\ready_github\ExamForge' # 按实际克隆目录修改
Set-Location (Join-Path $ProjectRoot 'ExamForge_JMeter_Performance')
.\monitor-docker.ps1 -DurationSeconds 600 -IntervalSeconds 5
```

采集 API、Worker、MySQL、Redis、RocketMQ Broker 的 CPU、内存、网络 I/O、块 I/O 和 PIDs。结果保存到 `results/docker-stats-*.csv`。

## 7. 结果文件与口径

每次测试生成：

```text
results/<plan>-exam<id>-<users>users-<timestamp>/
├─ results.jtl
├─ report/index.html
├─ jmeter.log
├─ run-info.txt
├─ summary.csv
├─ summary.txt
├─ verification.csv   # full 计划
└─ verification.txt   # full 计划
```

`summary.csv/txt` 按 HTTP 请求统计 Count、Errors、ErrorRate、Avg、P90、P95、P99、Max，并给出近似 HTTP TPS；内部全员屏障样本单独计数，不混入 HTTP 请求数和 TPS。HTML Dashboard 用于进一步分析。`verification.txt` 是 MySQL 端最终业务核验结果。

也可以单独重新执行阅卷核验：

```powershell
.\verify-full-run.ps1 `
  -AccountStart 1001 `
  -AccountCount 1000
```

或在 MySQL 中手动执行 `jmeter/post-run-check.sql`，先把 `@exam_id` 改为本轮考试 ID。

## 8. 发生错误时先保留证据

如果出现连接拒绝、HTTP 500 或错误率不为0，不要立即重跑同一批账号。先保留当前 `results/<run-name>/`，并在主项目根目录检查：

```powershell
docker compose ps
docker inspect examforge-api --format "Status={{.State.Status}} RestartCount={{.RestartCount}} OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}"
docker compose logs --since=15m --timestamps api worker mysql redis
```

将 JMeter 的 `summary.txt`、`verification.txt`、Docker 资源 CSV 与上述日志一起分析，区分真实业务失败、服务进程不可用、异步阅卷尚未完成和 JMeter 后续请求级联失败。

## 9. 简历数据口径

只有在 JMeter 请求错误率为0、1000条考试记录均为 `SUBMITTED`、10,000条答案记录齐全、1000条成绩均为 `COMPLETED`、GRADE Outbox 发送完成后，才可以写“完成1000名虚拟用户全链路测试”。

TPS、P95/P99、错误率必须取自最终 JTL；CPU/内存必须取自同一轮 Docker 监控。不要把虚拟用户数写成 TPS，也不要把尚未完成的异步阅卷写成“1000份成绩全部生成”。
