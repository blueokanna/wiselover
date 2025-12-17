use once_cell::sync::Lazy;
use rsntp::SntpClient;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const NTP_SERVERS: &[&str] = &[
    "ntp.aliyun.com",      // 阿里云
    "ntp.tencent.com",     // 腾讯云
    "ntp.ntsc.ac.cn",      // 国家授时中心
    "cn.pool.ntp.org",     // 中国区 NTP 池
    "time.google.com",     // Google
    "time.apple.com",      // Apple
    "time.cloudflare.com", // Cloudflare
    "time.windows.com",    // Windows 默认
    "pool.ntp.org",        // 全球 NTP 池
];

static TIME_OFFSET: AtomicI64 = AtomicI64::new(0);

static LAST_SYNC_TIME: AtomicI64 = AtomicI64::new(0);

const SYNC_INTERVAL_MS: i64 = 3600 * 1000;

const RETRY_INTERVAL_MS: i64 = 60 * 1000;

const NTP_TIMEOUT_SECS: u64 = 3;

const MAX_TIME_OFFSET_MS: i64 = 24 * 3600 * 1000;

static RUNTIME: Lazy<tokio::runtime::Runtime> = Lazy::new(|| {
    tokio::runtime::Runtime::new().expect("Failed to create Tokio runtime for time synchronization")
});

pub fn time_sync() -> i64 {
    if let Ok(handle) = tokio::runtime::Handle::try_current() {
        handle.block_on(time_sync_async())
    } else {
        RUNTIME.block_on(time_sync_async())
    }
}

pub async fn time_sync_async() -> i64 {
    // 获取当前系统时间
    let now_sys = match get_system_time_millis() {
        Some(time) => time,
        None => {
            // 系统时间获取失败，返回上次缓存的偏移量加上当前估算时间
            // 这种情况极少发生，但需要处理以避免 panic
            let offset = TIME_OFFSET.load(Ordering::Relaxed);
            return SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as i64
                + offset;
        }
    };

    let last_sync = LAST_SYNC_TIME.load(Ordering::Relaxed);
    let needs_sync = last_sync == 0 || (now_sys - last_sync).abs() > SYNC_INTERVAL_MS;

    if needs_sync {
        if let Some(ntp_millis) = fetch_ntp_time_async().await {
            let offset = ntp_millis - now_sys;

            if offset.abs() <= MAX_TIME_OFFSET_MS {
                TIME_OFFSET.store(offset, Ordering::Relaxed);
                LAST_SYNC_TIME.store(now_sys, Ordering::Relaxed);
                return ntp_millis;
            } else {
            }
        } else {
            let backoff_time = now_sys - (SYNC_INTERVAL_MS - RETRY_INTERVAL_MS);
            LAST_SYNC_TIME.store(backoff_time, Ordering::Relaxed);
        }
    }

    let offset = TIME_OFFSET.load(Ordering::Relaxed);
    now_sys + offset
}

fn get_system_time_millis() -> Option<i64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|dur| {
            // 检查是否会溢出 i64
            let millis = dur.as_millis();
            if millis <= i64::MAX as u128 {
                Some(millis as i64)
            } else {
                None
            }
        })
}

async fn fetch_ntp_time_async() -> Option<i64> {
    for &server in NTP_SERVERS {
        let server_str = server.to_string();
        match tokio::time::timeout(
            Duration::from_secs(NTP_TIMEOUT_SECS),
            tokio::task::spawn_blocking(move || {
                let client = SntpClient::new();
                client.synchronize(&server_str)
            }),
        )
        .await
        {
            Ok(Ok(Ok(result))) => {
                if let Ok(dt) = result.datetime().into_chrono_datetime() {
                    let timestamp_millis = dt.timestamp_millis();
                    if timestamp_millis > 0 && timestamp_millis < i64::MAX {
                        return Some(timestamp_millis);
                    }
                }
            }
            Ok(Ok(Err(_))) => {
                continue;
            }
            Ok(Err(_)) => {
                continue;
            }
            Err(_) => {
                continue;
            }
        }
    }

    None
}
