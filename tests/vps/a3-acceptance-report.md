# A3 Ubuntu 24.04 VPS 验收报告（脱敏）

- 测试日期：2026-08-13（Asia/Shanghai）
- 测试范围：用户明确提供的 Ubuntu 24.04 测试 VPS；不涉及生产节点
- 报告约束：不记录公网地址、密码、Token、UUID、私钥、完整配置或订阅 URL

## 结论

A3 验收通过。当前测试机的 sing-box 服务、健康检查 timer、配置检查和故障恢复均通过；正式配置在故障注入前后哈希一致（仅记录前缀 `c2cf17d68385`）。本阶段没有升级核心二进制、修改 SSH 或刷新防火墙。

## 基线与发现

| 项目 | 结果 |
|---|---|
| 系统/架构 | Ubuntu 24.04 LTS / x86_64 |
| 资源 | 1 vCPU / 约 1 GiB RAM |
| 当前 sing-box 核心 | 1.13.18 |
| 当前仓库 release marker | v1.0.0 |
| 活动配置 | `/etc/s-box/sb.json`，权限 0600，核心 `check` 退出码 0 |
| 主服务 | `sing-box.service` active、enabled |
| 健康定时器 | `sing-box-yg-health.timer` active、enabled |
| 防火墙边界 | UFW 不可用；nftables 仅做只读摘要，未执行全局刷新或规则改写 |

首次只读基线发现健康服务原先反复以 `226/NAMESPACE` 失败：unit 声明了
`ReadWritePaths=/var/lib/sing-box-yg`，但目录不存在，同时目标机缺少
`/usr/local/lib/sing-box-yg/sb-doctor.sh`。这属于部署/维护缺陷，不是核心配置本身的失败。

## 已实施的测试机修复

仅在测试机安装了当前 A3 分支已有的 `scripts/sb-doctor.sh`，并应用健康服务 unit：

- 增加 `StateDirectory=sing-box-yg` 与 `StateDirectoryMode=0700`，让 systemd 负责创建状态目录；
- 保留 `NoNewPrivileges`、`PrivateTmp`、`ProtectHome`、`ProtectSystem` 等限制；
- `/var/lib/sing-box-yg` 最终权限 0700，doctor 脚本权限 0755；
- 手动启动健康服务退出码 0，结果为 `success`；oneshot 服务随后显示 `inactive/dead` 属正常状态。

核心二进制、SSH 和防火墙没有被 A3 修复步骤改写；活动配置只在故障注入期间短暂替换，随后按备份恢复并复核哈希一致。

## 备份与服务验收

写操作前创建了 root-only 的显式备份目录 `/tmp/sbyg-a3/backup-a3-final-20260813`，目录权限 0700；配置、主服务 unit、健康服务 unit、timer 和 release marker 均写入备份，`SHA256SUMS` 全部校验通过。

最终脱敏快照：

| 检查 | 结果 |
|---|---|
| A3 `check` helper | 退出码 0 |
| `sing-box check -c /etc/s-box/sb.json` | 退出码 0 |
| `sing-box.service` | active / enabled，结果 success，主进程状态 0 |
| 健康 timer | active / enabled |
| 健康服务手动运行 | 退出码 0，结果 success |
| 配置/状态权限 | 配置 0600；状态目录 0700；doctor 0755 |
| 临时无效文件 | 0 个残留 |

## 故障注入与恢复

在备份和健康检查通过后，短暂把无效 JSON 注入正式配置，以触发
`sing-box.service` 的 `ExecStartPre=sing-box check` 守卫：

| 步骤 | 结果 |
|---|---|
| 无效配置 `check` | 退出码 1，被拒绝 |
| 使用无效配置重启服务 | 退出码 1；服务未以坏配置运行 |
| 从显式备份恢复配置 | 退出码 0 |
| 恢复后核心 `check` | 退出码 0 |
| 恢复后服务 | active |
| 恢复前后配置摘要 | 一致，哈希前缀均为 `c2cf17d68385` |

第一次故障注入草稿暴露了“未先建立配置备份就进入恢复”的流程缺口；该次结果不计入通过，随后使用现有 `.last-known-good/sb.json` 立即恢复服务，并补强了 A3 helper：新增显式 `backup` 子命令、备份清单校验，以及主服务/健康服务相关 unit 的安全恢复。最终故障注入按新流程重跑并通过。

## 本地回归与限制

- `tests/run.sh`：退出码 0；所有可运行测试通过。
- `bash -n tests/vps/*.sh`：通过。
- 本地环境没有 `jq`，因此 `port updates`、`config compatibility`、`integration smoke` 三项按测试套件约定标记为 SKIP，不是新增失败。
- `sb10.json` 在当前 1.13.18 核心下检查失败，而活动 `sb.json` 与 `sb11.json` 检查通过；这是旧核心/旧配置兼容性待后续单独验证的事项，不判定为活动配置故障。
- A3 未做真实客户端跨公网代理链路验收，也未把 1.13.18 宣称为“最新版本”；核心升级和旧配置矩阵应在后续维护阶段单独评估。
