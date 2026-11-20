<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { api } from '../api';
import { useRouter } from 'vue-router';
import { ElMessage } from 'element-plus';

const rows = ref<any[]>([]);
const loading = ref(true);
const router = useRouter();

async function load() {
  loading.value = true;
  try {
    const data = await api.availableExams();
    rows.value = Array.isArray(data) ? data : [];
  } catch {
    rows.value = [];
  } finally {
    loading.value = false;
  }
}

async function start(id: number) {
  try {
    const attempt: any = await api.startExam(id);
    if (!attempt?.attemptId) {
      throw new Error('考试记录创建失败');
    }
    await router.push(`/candidate/attempt/${attempt.attemptId}`);
  } catch (error: any) {
    ElMessage.error(error?.message || '进入考试失败');
  }
}

onMounted(load);
</script>

<template>
  <div class="page">
    <div class="page-header">
      <div>
        <h2 class="page-title">可参加考试</h2>
        <p class="muted">选择考试进入答题，考试开始后倒计时自动运行</p>
      </div>
    </div>

    <div v-loading="loading" class="stat-grid" style="grid-template-columns:repeat(auto-fit,minmax(260px,1fr))">
      <div v-for="e in rows" :key="e.id" class="content-card">
        <el-tag type="success">可参加</el-tag>
        <h3>{{ e.title }}</h3>
        <p class="muted">{{ e.description }}</p>
        <p>题目：{{ e.questionCount }} 道</p>
        <p>时长：{{ e.durationMinutes }} 分钟</p>
        <p class="muted">截止：{{ e.endTime }}</p>
        <el-button type="primary" @click="start(e.id)">进入考试</el-button>
      </div>
      <el-empty v-if="!loading && !rows.length" description="当前没有可参加的考试" />
    </div>
  </div>
</template>
