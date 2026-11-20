package com.examforge.job;
import com.xxl.job.core.executor.impl.XxlJobSpringExecutor;import org.springframework.beans.factory.annotation.Value;import org.springframework.context.annotation.*;
@Configuration @Profile("worker")public class XxlJobConfig{
 @Bean public XxlJobSpringExecutor xxlJobExecutor(@Value("${xxl.job.admin.addresses}")String addresses,@Value("${xxl.job.accessToken}")String token,@Value("${xxl.job.executor.appname}")String appName,@Value("${xxl.job.executor.address:}")String address,@Value("${xxl.job.executor.ip:}")String ip,@Value("${xxl.job.executor.port:9998}")int port,@Value("${xxl.job.executor.logpath:./logs/xxl-job}")String path,@Value("${xxl.job.executor.logretentiondays:30}")int days){XxlJobSpringExecutor e=new XxlJobSpringExecutor();e.setAdminAddresses(addresses);e.setAccessToken(token);e.setAppname(appName);e.setAddress(address);e.setIp(ip);e.setPort(port);e.setLogPath(path);e.setLogRetentionDays(days);return e;}
}
