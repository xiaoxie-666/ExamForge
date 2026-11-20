<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, nextTick } from 'vue';
import * as echarts from 'echarts';
import { api } from '../api';

const d = ref<any>({
  users: 0,
  questions: 0,
  exams: 0,
  attempts: 0,
  pendingGrades: 0,
});

const chartEl = ref<HTMLDivElement | null>(null);
let chart: echarts.ECharts | null = null;

function draw() {
  if (!chartEl.value) return;
  if (!chart) chart = echarts.init(chartEl.value);

  chart.setOption({
    tooltip: { trigger: 'axis' },
    grid: { left: 35, right: 20, top: 25, bottom: 30 },
    xAxis: {
      type: 'category',
      data: ['用户', '题目', '考试', '考试人次'],
    },
    yAxis: { type: 'value', minInterval: 1 },
    series: [{
      type: 'bar',
      barWidth: 42,
      data: [d.value.users, d.value.questions, d.value.exams, d.value.attempts],
      itemStyle: { borderRadius: [6, 6, 0, 0] },
    }],
  });
}

function resize() {
  chart?.resize();
}

onMounted(async () => {
  d.value = await api.dashboard();
  await nextTick();
  draw();
  window.addEventListener('resize', resize);
});

onBeforeUnmount(() => {
  window.removeEventListener('resize', resize);
  chart?.dispose();
  chart = null;
});
</script>

<template>
  <div class="page">
    <div class="page-header">
      <div>
        <h2 class="page-title">数据总览</h2>
        <p class="muted">ExamForge 运行概况</p>
      </div>
      <el-tag type="success">系统运行中</el-tag>
    </div>

    <div class="stat-grid">
      <div class="stat-card">
        <div class="stat-label">用户总数</div>
        <div class="stat-value">{{ d.users }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">题库题目</div>
        <div class="stat-value">{{ d.questions }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">考试场次</div>
        <div class="stat-value">{{ d.exams }}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">考试人次</div>
        <div class="stat-value">{{ d.attempts }}</div>
      </div>
    </div>

    <div class="content-card" style="margin-top: 18px">
      <h3>业务数据统计</h3>
      <div ref="chartEl" style="height: 280px; width: 100%" />
    </div>

    <div class="content-card" style="margin-top: 18px">
      <h3>业务流程</h3>
      <el-steps :active="6" finish-status="success" align-center>
        <el-step title="题库建设" description="题目维护" />
        <el-step title="试卷组卷" description="选题与分值配置" />
        <el-step title="考试发布" description="考试准入控制" />
        <el-step title="在线答题" description="缓存与持久化" />
        <el-step title="主动/超时交卷" description="状态原子转换" />
        <el-step title="RocketMQ 异步阅卷" description="消息投递与消费" />
        <el-step title="成绩统计" description="人工评分与成绩汇总" />
      </el-steps>

      <p class="muted" style="margin-top: 24px; line-height: 1.8">
        考生交卷后，系统在同一数据库事务中更新考试状态并写入 Outbox 事件，
        再由发布器投递至 RocketMQ。Worker 自动批改客观题，主观题进入人工阅卷队列；
        XXL-Job 定期扫描超时考试及异常状态，执行自动交卷与任务补偿。
        当前待人工阅卷：{{ d.pendingGrades }} 份。
      </p>
    </div>
  </div>
</template>
