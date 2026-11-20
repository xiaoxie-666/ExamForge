
<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api'
import { ElMessage, ElMessageBox } from 'element-plus'

// ==================== 类型定义 ====================

interface ExamQuestion {
  questionId: number
  answer?: string | null
  version?: number
  type: string
  content: string
  options: string[]
}

interface ExamAttempt {
  attemptId: number
  examTitle: string
  questions: ExamQuestion[]
  deadlineAt: string
  status: string
}

// ==================== 基础状态 ====================

const route = useRoute()
const router = useRouter()

const attempt = ref<ExamAttempt | null>(null)
const index = ref(0)

const answers = reactive<Record<number, string>>({})
const versions = reactive<Record<number, number>>({})
const multi = reactive<Record<number, string[]>>({})

const remaining = ref(0)
const saving = ref(false)
const saveText = ref('自动保存已开启')
const submitting = ref(false)

let timer: ReturnType<typeof setInterval> | null = null
let debounce: ReturnType<typeof setTimeout> | null = null

// ==================== 当前题目与倒计时 ====================

const current = computed<ExamQuestion | undefined>(() => {
  return attempt.value?.questions[index.value]
})

const timeText = computed(() => {
  const s = Math.max(0, remaining.value)

  return `${String(Math.floor(s / 3600)).padStart(2, '0')}:${String(
    Math.floor((s % 3600) / 60)
  ).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
})

// ==================== 答案处理 ====================

function code(option: string): string {
  const i = option.indexOf('.')
  return i > 0 ? option.slice(0, i).trim() : option
}

// ==================== 加载考试 ====================

async function load() {
  const data = await api.attempt(
    Number(route.params.id)
  ) as ExamAttempt

  attempt.value = data

  for (const q of data.questions) {
    answers[q.questionId] = q.answer || ''
    versions[q.questionId] = q.version || 0

    multi[q.questionId] = (q.answer || '')
      .split(',')
      .filter(Boolean)
  }

  remaining.value = Math.max(
    0,
    Math.floor(
      (new Date(data.deadlineAt).getTime() - Date.now()) / 1000
    )
  )

  if (data.status === 'IN_PROGRESS') {
    timer = setInterval(() => {
      remaining.value = Math.max(0, remaining.value - 1)

      if (remaining.value === 0) {
        submit(true)
      }
    }, 1000)
  }
}

// ==================== 自动保存 ====================

function scheduleSave(q: ExamQuestion) {
  saveText.value = '答案待保存…'

  if (debounce) {
    clearTimeout(debounce)
  }

  debounce = setTimeout(() => {
    save(q)
  }, 450)
}

// ==================== 多选题处理 ====================

function onMultiChange(values: unknown[], q: ExamQuestion) {
  const selected = values.map(value => String(value))

  multi[q.questionId] = selected

  answers[q.questionId] = selected
    .slice()
    .sort()
    .join(',')

  scheduleSave(q)
}

// ==================== 保存答案 ====================

async function save(q: ExamQuestion): Promise<boolean> {
  if (!q || attempt.value?.status !== 'IN_PROGRESS') {
    return false
  }

  saving.value = true

  try {
    const r: any = await api.saveAnswer(
      Number(route.params.id),
      {
        questionId: q.questionId,
        answer: answers[q.questionId] || '',
        version: versions[q.questionId] ?? 0
      }
    )

    versions[q.questionId] = r.version
    saveText.value = '答案已保存'

    return true
  } catch {
    saveText.value = '保存失败，请检查网络'
    return false
  } finally {
    saving.value = false
  }
}

// ==================== 提交试卷 ====================

async function submit(auto = false) {
  const activeAttempt = attempt.value

  if (
    !activeAttempt ||
    activeAttempt.status !== 'IN_PROGRESS' ||
    submitting.value
  ) {
    return
  }

  if (!auto) {
    try {
      await ElMessageBox.confirm(
        '确认交卷？交卷后不能再修改答案。',
        '交卷确认'
      )
    } catch {
      return
    }
  }

  submitting.value = true

  if (timer) {
    clearInterval(timer)
    timer = null
  }

  if (debounce) {
    clearTimeout(debounce)
    debounce = null
  }

  try {
    if (!auto) {
      for (const q of activeAttempt.questions) {
        const ok = await save(q)

        if (!ok) {
          ElMessage.error(
            '部分答案保存失败，请检查网络后重试交卷'
          )
          return
        }
      }
    }

    await api.submitExam(Number(route.params.id))

    ElMessage.success(
      auto ? '考试时间结束，已自动交卷' : '交卷成功'
    )

    router.push('/results')
  } finally {
    submitting.value = false
  }
}

// ==================== 生命周期 ====================

onMounted(load)

onUnmounted(() => {
  if (timer) {
    clearInterval(timer)
  }

  if (debounce) {
    clearTimeout(debounce)
  }
})
</script>

<template>
  <div class="page" v-if="attempt">
    <div class="page-header">
      <div>
        <h2 class="page-title">{{ attempt.examTitle }}</h2>

        <div class="exam-meta">
          <span>考试记录：{{ attempt.attemptId }}</span>
          <span>题目：{{ attempt.questions.length }} 道</span>
          <span>
            剩余时间：
            <b style="color:#dc2626">{{ timeText }}</b>
          </span>
        </div>
      </div>

      <el-button
        type="danger"
        :loading="submitting"
        :disabled="attempt.status !== 'IN_PROGRESS'"
        @click="submit(false)"
      >
        交卷
      </el-button>
    </div>

    <div class="exam-layout">
      <div class="question-card" v-if="current">
        <div style="display:flex;justify-content:space-between">
          <el-tag>{{ current.type }}</el-tag>

          <span class="muted">
            {{ index + 1 }} / {{ attempt.questions.length }}
          </span>
        </div>

        <h3 style="line-height:1.7;margin-top:24px">
          {{ current.content }}
        </h3>

        <!-- 单选题、判断题 -->
        <div
          v-if="current.type === 'SINGLE' || current.type === 'JUDGE'"
          class="answer-options"
        >
          <el-radio-group
            v-model="answers[current.questionId]"
            @change="scheduleSave(current)"
          >
            <el-radio
              v-for="o in current.options"
              :key="o"
              :label="code(o)"
            >
              {{ o }}
            </el-radio>
          </el-radio-group>
        </div>

        <!-- 多选题 -->
        <div
          v-else-if="current.type === 'MULTIPLE'"
          class="answer-options"
        >
          <el-checkbox-group
            :model-value="multi[current.questionId] || []"
            @change="onMultiChange($event, current)"
          >
            <el-checkbox
              v-for="o in current.options"
              :key="o"
              :label="code(o)"
            >
              {{ o }}
            </el-checkbox>
          </el-checkbox-group>
        </div>

        <!-- 主观题 -->
        <div v-else class="answer-options">
          <el-input
            v-model="answers[current.questionId]"
            type="textarea"
            :rows="5"
            placeholder="请输入答案"
            @input="scheduleSave(current)"
          />
        </div>

        <div style="display:flex;justify-content:space-between;margin-top:34px">
          <el-button
            :disabled="index === 0"
            @click="index--"
          >
            上一题
          </el-button>

          <span class="save-state">
            {{ saving ? '保存中…' : saveText }}
          </span>

          <el-button
            type="primary"
            :disabled="index === attempt.questions.length - 1"
            @click="index++"
          >
            下一题
          </el-button>
        </div>
      </div>

      <div class="question-card" v-else>
        <el-empty description="暂无试题" />
      </div>

      <!-- 答题卡 -->
      <aside class="question-nav">
        <h4>答题卡</h4>

        <p class="muted" style="font-size:12px">
          绿色表示已作答
        </p>

        <div class="q-grid">
          <button
            v-for="(q, i) in attempt.questions"
            :key="q.questionId"
            :class="{
              active: index === Number(i),
              answered: !!answers[q.questionId]
            }"
            @click="index = Number(i)"
          >
            {{ Number(i) + 1 }}
          </button>
        </div>

        <el-divider />

        <p>
          已答：
          {{ Object.values(answers).filter(Boolean).length }}
          / {{ attempt.questions.length }}
        </p>

        <el-button
          type="danger"
          plain
          style="width:100%"
          @click="submit(false)"
        >
          提交试卷
        </el-button>
      </aside>
    </div>
  </div>

  <el-empty v-else description="正在加载考试..." />
</template>
