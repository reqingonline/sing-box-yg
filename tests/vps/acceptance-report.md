# 一次性 VPS 验收报告（脱敏）

- 日期：2026-07-18（Asia/Shanghai）
- 系统：Ubuntu 24.04 LTS，amd64，1 vCPU / 1 GiB RAM
- 防火墙基线：UFW active；SSH TCP 规则存在
- 官方核心：稳定版 1.13.14、预发布版 1.14.0-alpha.47，资产均通过 Release API SHA-256 digest 校验

| 验收项 | 结果 | 证据摘要 |
|---|---|---|
| Linux Release 预检 | PASS | ShellCheck、单元/集成、安装器失败路径退出 0 |
| 1.13 / 1.14 配置 | PASS | 两个真实核心 `check` 退出 0 |
| Reality + Hysteria2 | PASS | 独立 systemd 服务，TCP/UDP 仅监听回环测试端口，稳定运行超过 60 秒 |
| 无效 JSON / 端口占用 | PASS | 失败被轮询发现，健康配置哈希恢复，服务重新 active |
| 坏摘要 / 截断包 | PASS | 安装器退出非零，旧安装逐文件摘要不变 |
| 防火墙隔离 | PASS | 仅移除 `SBYG_PREROUTING`；无关测试链在断言时仍存在 |
| UFW、SSH、无关文件 | PASS | 清理前后 UFW active、SSH 规则计数及 sentinel 内容一致 |
| 测试资源清理 | PASS | unit、进程、项目链和监听均已移除 |

报告未记录公网地址、密码、私钥、UUID、token、节点 URI 或完整订阅 URL。测试主机密码曾出现在用户截图中，投入其他用途前必须重建或轮换。
