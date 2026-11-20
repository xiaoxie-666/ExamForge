import http from './http';

// The response interceptor in http.ts unwraps AxiosResponse.data at runtime.
// Axios' default method signatures still describe AxiosResponse, so these
// small wrappers make the unwrapped API contract explicit to Vue pages.
const get = (url: string, config?: any): Promise<any> => http.get<any, any>(url, config);
const post = (url: string, data?: any, config?: any): Promise<any> => http.post<any, any>(url, data, config);
const put = (url: string, data?: any, config?: any): Promise<any> => http.put<any, any>(url, data, config);
const del = (url: string, config?: any): Promise<any> => http.delete<any, any>(url, config);

export const api = {
  login: (d: any) => post('/auth/login', d),
  me: () => get('/auth/me'),
  dashboard: () => get('/admin/dashboard'),
  users: (p: any) => get('/admin/users', { params: p }),
  createUser: (d: any) => post('/admin/users', d),
  setUserStatus: (id: number, status: number) => put(`/admin/users/${id}/status`, null, { params: { status } }),
  questions: (p: any) => get('/questions', { params: p }),
  createQuestion: (d: any) => post('/questions', d),
  updateQuestion: (id: number, d: any) => put(`/questions/${id}`, d),
  deleteQuestion: (id: number) => del(`/questions/${id}`),
  exams: () => get('/exams'),
  createExam: (d: any) => post('/exams', d),
  publishExam: (id: number) => put(`/exams/${id}/publish`),
  closeExam: (id: number) => put(`/exams/${id}/close`),
  deleteExam: (id: number) => del(`/exams/${id}`),
  availableExams: () => get('/candidate/exams'),
  startExam: (id: number) => post(`/candidate/exams/${id}/start`),
  attempt: (id: number) => get(`/candidate/attempts/${id}`),
  saveAnswer: (id: number, d: any) => put(`/candidate/attempts/${id}/answers`, d),
  submitExam: (id: number) => post(`/candidate/attempts/${id}/submit`),
  results: () => get('/candidate/results'),
  pendingGrades: () => get('/grading/pending'),
  gradingDetail: (id: number) => get(`/grading/attempts/${id}`),
  manualGrade: (id: number, d: any) => post(`/grading/attempts/${id}/subjective`, d),
  statistics: () => get('/grading/statistics'),
  statisticsDetail: (examId: number) => get(`/grading/statistics/${examId}`),
};
