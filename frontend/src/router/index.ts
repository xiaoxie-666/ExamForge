import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from '../stores/auth';
import LoginView from '../views/LoginView.vue';
import MainLayout from '../layouts/MainLayout.vue';

function homePath(role?: string) {
  return role === 'STUDENT' ? '/candidate' : '/dashboard';
}

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', component: LoginView },
    {
      path: '/',
      component: MainLayout,
      children: [
        { path: '', redirect: () => homePath(useAuthStore().user?.role) },
        { path: 'dashboard', component: () => import('../views/DashboardView.vue'), meta: { roles: ['ADMIN', 'TEACHER'] } },
        { path: 'questions', component: () => import('../views/QuestionsView.vue'), meta: { roles: ['ADMIN', 'TEACHER'] } },
        { path: 'exams', component: () => import('../views/ExamsView.vue'), meta: { roles: ['ADMIN', 'TEACHER'] } },
        { path: 'users', component: () => import('../views/UsersView.vue'), meta: { roles: ['ADMIN'] } },
        { path: 'candidate', component: () => import('../views/CandidateView.vue'), meta: { roles: ['STUDENT'] } },
        { path: 'candidate/attempt/:id', component: () => import('../views/ExamTakingView.vue'), meta: { roles: ['STUDENT'] } },
        { path: 'results', component: () => import('../views/ResultsView.vue'), meta: { roles: ['STUDENT'] } },
        { path: 'grading', component: () => import('../views/GradingView.vue'), meta: { roles: ['ADMIN', 'TEACHER'] } },
        { path: 'statistics', component: () => import('../views/StatisticsView.vue'), meta: { roles: ['ADMIN', 'TEACHER'] } },
      ],
    },
  ],
});

router.beforeEach(to => {
  const auth = useAuthStore();

  // A logged-in user should never be left on the login page.
  if (to.path === '/login') {
    if (!auth.isLoggedIn) return true;
    return homePath(auth.user?.role);
  }

  if (!auth.isLoggedIn) {
    return { path: '/login', query: { redirect: to.fullPath } };
  }

  // The root route is role-aware. Do not pass through the dashboard first,
  // otherwise STUDENT accounts can be redirected through an unauthorized
  // intermediate route before reaching /candidate.
  if (to.path === '/') {
    return homePath(auth.user?.role);
  }

  const roles = to.meta.roles as string[] | undefined;
  if (roles && (!auth.user || !roles.includes(auth.user.role))) {
    return homePath(auth.user?.role);
  }

  return true;
});

export default router;
