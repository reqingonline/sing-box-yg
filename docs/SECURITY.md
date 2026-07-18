# 安全边界

## 项目拥有的范围

- 程序：`/usr/local/lib/sing-box-yg`、`/usr/bin/sb`。
- 配置与运行文件：`/etc/s-box`。
- 事务与健康状态：`/var/lib/sing-box-yg`、`/run/sing-box-yg`。
- systemd/OpenRC 服务、`sing-box-yg-health` 定时器。
- 防火墙只拥有 `SBYG_PREROUTING` 链及带 `sing-box-yg` 注释的跳转/规则。

卸载不会刷新全局 iptables/nftables，不会关闭 UFW/firewalld，不会更改默认策略，也不会删除未登记的用户目录。VPS 卸载默认把配置移到 `/var/backups/sing-box-yg/<时间>`，以便恢复。

## 密钥与订阅

- 密钥目录、配置和 token 使用 `0700/0600` 权限；日志与 `sb doctor` 对 UUID、密码、私钥、token 和完整订阅 URL 脱敏。
- 订阅 HTTP 服务默认监听 `127.0.0.1`，随机访问 token 与节点 UUID 相互独立。
- 公网发布必须经过 HTTPS 和身份验证；不得把 BusyBox HTTP 服务直接暴露到公网。
- Cloudflare Tunnel token 通过 `--token-file` 读取，不能出现在进程参数、cron 或日志中。

## 供应链

稳定安装器只接受 Release 包和对应 `SHA256SUMS`。sing-box、cloudflared 和规则资产读取 GitHub Release API 的 SHA-256 digest 后再原子安装。无法确认来源的 WARP-plus 二进制和外部 `curl | bash` 入口已停用。

发现漏洞时请提交不含真实节点、密码、IP 或订阅地址的私密报告。测试 VPS 使用完毕后应重建或轮换已展示过的密码。
