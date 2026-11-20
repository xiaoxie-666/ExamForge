package com.examforge.config;

import org.redisson.Redisson;
import org.redisson.api.RedissonClient;
import org.redisson.config.Config;
import org.redisson.config.SingleServerConfig;
import org.springframework.boot.autoconfigure.data.redis.RedisProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;

/**
 * Redisson client configuration.
 *
 * Uses the same Redis endpoint as Spring Data Redis so Lua scripts and
 * distributed locks share the application's Redis instance.
 */
@Configuration
public class RedissonConfig {

    @Bean(destroyMethod = "shutdown")
    public RedissonClient redissonClient(RedisProperties properties) {
        Config config = new Config();
        config.setLockWatchdogTimeout(30_000L);

        SingleServerConfig server = config.useSingleServer()
                .setAddress("redis://" + properties.getHost() + ":" + properties.getPort())
                .setDatabase(properties.getDatabase())
                .setConnectionMinimumIdleSize(8)
                .setConnectionPoolSize(64);

        if (StringUtils.hasText(properties.getPassword())) {
            server.setPassword(properties.getPassword());
        }

        return Redisson.create(config);
    }
}
