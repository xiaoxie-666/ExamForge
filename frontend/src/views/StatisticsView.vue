<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import * as echarts from 'echarts';
import { api } from '../api';

const route = useRoute();

const summaries = ref<any[]>([]);
const selectedExamId = ref<number | null>(null);
const detail = ref<any>(null);
const loading = ref(false);

const chartEl = ref<HTMLDivElement | null>(null);
let chart: echarts.ECharts | null = null;

function statusType(status: string) {
  if (status === 'PUBLISHED') return 'success';
  if (status === 'CLOSED') return 'info';
  return 'warning';
}

function statusLabel(status: string) {
  if (status === 'PUBLISHED') return '已发布';
  if (status === 'CLOSED') return '已结束';
  return '草稿';
}

async function load() {
  loading.value = true;
  try {
    summaries.value = await api.statistics();

    if (!summaries.value.length) {
      selectedExamId.value = null;
      detail.value = null;
      return;
    }

    const queryId = Number(route.query.examId);
    const exists = Number.isFinite(queryId)
      && summaries.value.some(item => Number(item.examId) === queryId);

    selectedExamId.value = exists ? queryId : Number(summaries.value[0].examId);
    await loadDetail(selectedExamId.value);
  } finally {
    loading.value = false;
  }
}

async function loadDetail(examId: number | null) {
  if (!examId) {
    detail.value = null;
    return;
  }

  detail.value = await api.statisticsDetail(examId);
  await nextTick();
  drawChart();
}

function drawChart() {
  if (!chartEl.value || !detail.value) return;

  if (!chart) {
    chart = echarts.init(chartEl.value);
  }

  const distribution = detail.value.distribution ?? [];

  chart.setOption({
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      formatter: (items: any[]) => {
        const item = items?.[0];
        const row = distribution[item?.dataIndex ?? 0];
        return `${row?.range ?? ''}<br/>人数：${row?.count ?? 0}<br/>占比：${row?.rate ?? 0}%`;
      },
    },
    grid: { left: 45, right: 25, top: 25, bottom: 35 },
    xAxis: {
      type: 'category',
      data: distribution.map((item: any) => item.range),
    },
    yAxis: {
      type: 'value',
      minInterval: 1,
    },
    series: [{
      type: 'bar',
      barWidth: 48,
      data: distribution.map((item: any) => item.count),
      itemStyle: { borderRadius: [6, 6, 0, 0] },
    }],
  });
}

function resize() {
  chart?.resize();
}

async function changeExam() {
  await loadDetail(selectedExamId.value);
}

onMounted(async () => {
  await load();
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
        <h2 class="page-title">成绩统计</h2>
        <p class="muted">基于真实考试记录与已完成阅卷结果统计成绩，及格线按总分 60% 计算</p>
      </div>
      <el-button :loading="loading" @click="load">刷新</el-button>
    </div>

    <div v-if="summaries.length" class="content-card" style="margin-bottom: 18px">
      <div class="toolbar" style="margin-bottom: 0">
        <span style="font-weight: 600">选择考试</span>
        <el-select
          v-model="selectedExamId"
          filterable
          style="width: min(520px, 100%)"
          @change="changeExam"
        >
          <el-option
            v-for="item in summaries"
            :key="item.examId"
            :value="item.examId"
            :label="`${item.examTitle}（${statusLabel(item.examStatus)}）`"
          />
        </el-select>
      </div>
    </div>

    <template v-if="detail">
      <div class="stat-grid">
        <div class="stat-card">
          <div class="stat-label">参考人数</div>
          <div class="stat-value">{{ detail.summary.participants }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">已交卷</div>
          <div class="stat-value">{{ detail.summary.submitted }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">已评分</div>
          <div class="stat-value">{{ detail.summary.graded }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">待评分</div>
          <div class="stat-value">{{ detail.summary.pending }}</div>
        </div>
      </div>

      <div class="stat-grid" style="margin-top: 16px">
        <div class="stat-card">
          <div class="stat-label">平均分</div>
          <div class="stat-value">
            {{ detail.summary.averageScore }} / {{ detail.summary.totalScore }}
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-label">最高分</div>
          <div class="stat-value">
            {{ detail.summary.highestScore }} / {{ detail.summary.totalScore }}
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-label">最低分</div>
          <div class="stat-value">
            {{ detail.summary.lowestScore }} / {{ detail.summary.totalScore }}
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-label">及格率</div>
          <div class="stat-value">{{ detail.summary.passRate }}%</div>
        </div>
      </div>

      <div class="content-card" style="margin-top: 18px">
        <div class="page-header" style="margin-bottom: 10px">
          <div>
            <h3 style="margin: 0">{{ detail.summary.examTitle }}</h3>
            <p class="muted" style="margin: 6px 0 0">
              成绩分布（按总分百分比）
            </p>
          </div>
          <el-tag :type="statusType(detail.summary.examStatus)">
            {{ statusLabel(detail.summary.examStatus) }}
          </el-tag>
        </div>
        <div ref="chartEl" style="height: 300px; width: 100%" />
        <el-empty
          v-if="!detail.ranking?.length"
          description="暂无已完成阅卷的成绩数据"
        />
      </div>

      <div class="content-card" style="margin-top: 18px">
        <div class="page-header" style="margin-bottom: 12px">
          <div>
            <h3 style="margin: 0">成绩明细</h3>
            <p class="muted" style="margin: 6px 0 0">
              仅展示已完成阅卷的真实成绩记录
            </p>
          </div>
          <el-tag type="info">{{ detail.ranking?.length ?? 0 }} 人</el-tag>
        </div>

        <el-table :data="detail.ranking" stripe>
          <el-table-column prop="rank" label="排名" width="80" />
          <el-table-column prop="studentName" label="考生" min-width="150" />
          <el-table-column prop="objectiveScore" label="客观题" width="110" />
          <el-table-column prop="subjectiveScore" label="主观题" width="110" />
          <el-table-column prop="totalScore" label="总分" width="110">
            <template #default="scope">
              <strong>{{ scope.row.totalScore }}</strong>
            </template>
          </el-table-column>
          <el-table-column prop="gradedAt" label="评分时间" min-width="170" />
        </el-table>

        <el-empty
          v-if="!detail.ranking?.length"
          description="完成考试并生成成绩后，这里会显示成绩明细"
        />
      </div>
    </template>

    <div v-else class="content-card">
      <el-empty description="暂无考试数据，请先创建并发布考试" />
    </div>
  </div>
</template>
