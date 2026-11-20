import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import { api } from '../api';

export const useAuthStore = defineStore('auth', () => {
  const token = ref(localStorage.getItem('examforge_token') || '');

  let storedUser: any = null;
  try {
    storedUser = JSON.parse(localStorage.getItem('examforge_user') || 'null');
  } catch {
    storedUser = null;
  }

  const user = ref<any>(storedUser);

  // A token without its user profile is not enough for role-based routing.
  const isLoggedIn = computed(() => !!token.value && !!user.value);

  async function login(username: string, password: string) {
    const r: any = await api.login({ username, password });

    if (!r?.token || !r?.role || !r?.userId) {
      throw new Error('登录响应缺少身份信息');
    }

    token.value = r.token;
    user.value = {
      id: r.userId,
      username: r.username,
      displayName: r.displayName,
      role: r.role,
    };

    localStorage.setItem('examforge_token', r.token);
    localStorage.setItem('examforge_user', JSON.stringify(user.value));
  }

  function logout() {
    token.value = '';
    user.value = null;
    localStorage.removeItem('examforge_token');
    localStorage.removeItem('examforge_user');
  }

  return { token, user, isLoggedIn, login, logout };
});
