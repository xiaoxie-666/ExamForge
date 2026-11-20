<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue';
import { api } from '../api';
import { ElMessage, ElMessageBox } from 'element-plus';

const rows = ref<any[]>([]);
const questions = ref<any[]>([]);
const dialog = ref(false);
const saving = ref(false);
const form = reactive<any>({
  title: '',
  description: '',
  startTime: '',
  endTime: '',
  durationMinutes: 60,
  questionIds: [],
});

// The backend CreateExamRequest uses java.time.LocalDateTime.
// Send ISO-8601 local datetime strings (with "T"), never a space separator.
const localInput = (offsetMs: number) =>
  new Date(Date.now() + offsetMs).toLocaleString('sv-SE').replace(' ', 'T');

function toApiLocalDateTime(value: string): string {
  const normalized = String(value ?? '').trim().replace(' ', 'T');
  const minutePrecision = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;
  const secondPrecision = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/;

  if (minutePrecision.test(normalized)) {
    return `${normalized}:00`;
  }
  if (secondPrecision.test(normalized)) {
    return normalized;
  }
  return '';
}

async function load() {
  rows.value = await api.exams();
}

async function open() {
  const q: any = await api.questions({ page: 1, size: 200 });
  questions.value = q.records ?? [];

  Object.assign(form, {
    title: '',
    description: '',
    startTime: localInput(60_000),
    endTime: localInput(24 * 60 * 60 * 1000),
    durationMinutes: 60,
    questionIds: [],
  });

  dialog.value = true;
}

async function save() {
  if (!form.title?.trim()) {
    ElMessage.error('请输入考试名称');
    return;
  }

  const startTime = toApiLocalDateTime(form.startTime);
  const endTime = toApiLocalDateTime(form.endTime);

  if (!startTime || !endTime) {
    ElMessage.error('考试时间格式无效，请重新选择开始时间和结束时间');
    return;
  }
  if (endTime <= startTime) {
    ElMessage.error('考试结束时间必须晚于开始时间');
    return;
  }
  if (!Array.isArray(form.questionIds) || form.questionIds.length === 0) {
    ElMessage.error('请至少选择一道试题');
    return;
  }

  saving.value = true;
  try {
    await api.createExam({
      ...form,
      startTime,
      endTime,
    });
    ElMessage.success('考试创建成功');
    dialog.value = false;
    await load();
  } finally {
    saving.value = false;
  }
}

async function publish(id: number) {
  await api.publishExam(id);
  ElMessage.success('考试已发布');
  await load();
}

async function closeExam(id: number) {
  try {
    await ElMessageBox.confirm(
      '关闭后，考生将无法新进入该场考试；已有考试记录和成绩仍会保留。',
      '关闭考试确认',
      { type: 'warning', confirmButtonText: '确认关闭', cancelButtonText: '取消' }
    );
  } catch {
    return;
  }

  await api.closeExam(id);
  ElMessage.success('考试已关闭');
  await load();
}

async function deleteExam(row: any) {
  try {
    await ElMessageBox.confirm(
      `确定删除考试「${row.title}」吗？删除后无法恢复；已有考生参加记录的考试不允许删除。`,
      '删除考试确认',
      {
        type: 'warning',
        confirmButtonText: '确认删除',
        cancelButtonText: '取消',
        distinguishCancelAndClose: true,
      }
    );
  } catch {
    return;
  }

  try {
    await api.deleteExam(row.id);
    ElMessage.success('考试已删除');
    await load();
  } catch {
    // The shared Axios interceptor already displays the backend error message.
    // For example, exams with candidate attempts are intentionally protected.
  }
}

onMounted(load);
</script>

<template>
  <div class="page">
    <div class="page-header">
      <div>
        <h2 class="page-title">考试管理</h2>
        <p class="muted">组卷、设置考试时间、发布考试并维护考试记录</p>
      </div>
      <el-button type="primary" @click="open">创建考试</el-button>
    </div>

    <div class="content-card">
      <el-table :data="rows" stripe>
        <el-table-column prop="id" label="ID" width="70" />
        <el-table-column prop="title" label="考试名称" min-width="220" />
        <el-table-column prop="questionCount" label="题目数" width="90" />
        <el-table-column prop="durationMinutes" label="时长（分钟）" width="120" />
        <el-table-column prop="startTime" label="开始时间" min-width="160" />
        <el-table-column prop="endTime" label="结束时间" min-width="160" />
        <el-table-column prop="status" label="状态" width="110">
          <template #default="scope">
            <el-tag
              :type="scope.row.status === 'PUBLISHED'
                ? 'success'
                : scope.row.status === 'CLOSED'
                  ? 'info'
                  : 'warning'"
            >
              {{ scope.row.status }}
            </el-tag>
          </template>
        </el-table-column>

        <el-table-column label="操作" width="220" fixed="right">
          <template #default="scope">
            <el-button
              v-if="scope.row.status === 'DRAFT'"
              link
              type="primary"
              @click="publish(scope.row.id)"
            >
              发布
            </el-button>
            <el-button
              v-if="scope.row.status === 'PUBLISHED'"
              link
              type="warning"
              @click="closeExam(scope.row.id)"
            >
              关闭
            </el-button>
            <el-button
              v-if="true"
              link
              type="danger"
              @click="deleteExam(scope.row)"
            >
              删除
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </div>

    <el-dialog v-model="dialog" title="创建考试" width="650px">
      <el-form label-position="top">
        <el-form-item label="考试名称">
          <el-input v-model="form.title" />
        </el-form-item>
        <el-form-item label="考试说明">
          <el-input v-model="form.description" type="textarea" />
        </el-form-item>
        <el-row :gutter="12">
          <el-col :span="12">
            <el-form-item label="开始时间">
              <el-date-picker
                v-model="form.startTime"
                type="datetime"
                format="YYYY-MM-DD HH:mm:ss"
                value-format="YYYY-MM-DDTHH:mm:ss"
                style="width: 100%"
              />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="结束时间">
              <el-date-picker
                v-model="form.endTime"
                type="datetime"
                format="YYYY-MM-DD HH:mm:ss"
                value-format="YYYY-MM-DDTHH:mm:ss"
                style="width: 100%"
              />
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="考试时长（分钟）">
          <el-input-number v-model="form.durationMinutes" :min="1" :max="600" />
        </el-form-item>
        <el-form-item label="选择试题">
          <el-select
            v-model="form.questionIds"
            multiple
            filterable
            style="width: 100%"
            placeholder="选择题目"
          >
            <el-option
              v-for="question in questions"
              :key="question.id"
              :label="`#${question.id} ${question.type} - ${question.content.slice(0, 40)}`"
              :value="question.id"
            />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">创建草稿</el-button>
      </template>
    </el-dialog>
  </div>
</template>
