import axios from 'axios';import {ElMessage} from 'element-plus';
const http=axios.create({baseURL:'/api',timeout:20000});
http.interceptors.request.use(c=>{const t=localStorage.getItem('examforge_token');if(t)c.headers.Authorization=`Bearer ${t}`;return c});
http.interceptors.response.use(r=>{const b=r.data;if(b&&typeof b.code==='number'&&b.code!==0){ElMessage.error(b.message||'请求失败');return Promise.reject(new Error(b.message||'请求失败'))}return b?.data??b},e=>{if(e.response?.status===401){localStorage.removeItem('examforge_token');localStorage.removeItem('examforge_user');if(location.pathname!='/login')location.href='/login'}ElMessage.error(e.response?.data?.message||e.message||'网络请求失败');return Promise.reject(e)});
export default http;
