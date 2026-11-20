<script setup lang="ts">
import { reactive, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../stores/auth';
import { ElMessage } from 'element-plus';

const auth = useAuthStore();
const router = useRouter();
const loading = ref(false);
const form = reactive({ username: '', password: '' });

async function submit() {
  if (loading.value) return;

  loading.value = true;
  try {
    await auth.login(form.username.trim(), form.password);

    // Navigate directly according to the authenticated role.
    // In particular, STUDENT must go to /candidate rather than
    // / -> /dashboard -> /candidate.
    const target = auth.user?.role === 'STUDENT' ? '/candidate' : '/dashboard';
    await router.replace(target);
    ElMessage.success('登录成功');
  } catch (error) {
    // The shared Axios interceptor already shows the server-side error.
    // Keep the page in place so the user can correct the credentials.
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="login-wrap">
    <div class="login-card">
      <div class="brand">ExamForge</div>
      <h1>欢迎回来</h1>
      <p class="muted">高并发在线考试与测评平台</p>
      <el-form label-position="top" @submit.prevent="submit">
        <el-form-item label="用户名">
          <el-input v-model="form.username" size="large" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input
            v-model="form.password"
            type="password"
            show-password
            size="large"
            @keyup.enter="submit"
          />
        </el-form-item>
        <el-button
          type="primary"
          size="large"
          style="width:100%"
          :loading="loading"
          @click="submit"
        >
          登录
        </el-button>
      </el-form>
      <p class="muted" style="font-size:12px;margin-top:20px">
        管理员：admin / Admin@123；教师：teacher / Teacher@123；考生：student / Student@123
      </p>
    </div>
  </div>
</template>
