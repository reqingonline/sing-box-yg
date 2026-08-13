# VPS validation helpers

These checks complement the fast shell tests in `tests/`.  Run them only on a
disposable VPS, after a normal installation has completed successfully.

The acceptance flow is split into `capture-baseline.sh`,
`release-acceptance.sh`, `failure-injection.sh`, and `cleanup-verify.sh`.
Each destructive phase requires explicit `SBYG_ACCEPTANCE_*` paths; none of
these helpers flushes a firewall or recursively targets a home directory.

```bash
bash tests/run.sh
bash tests/vps/run-distribution-matrix.sh
bash tests/vps/run-host-integration.sh --live
```

`run-distribution-matrix.sh` needs Docker and verifies the package-manager
selection used by supported distribution families.  `run-host-integration.sh`
requires root and an installed sing-box service; it deliberately writes an
invalid temporary configuration to prove that the restart guard restores the
last known-good configuration.  The script refuses to run unless `--live` is
passed explicitly, and restores the configuration before it exits.

For a longer observation, install `monitor-health.sh` with the accompanying
systemd service and timer units.  It records service state, `sing-box check`,
disk use, and post-install service errors without changing the configuration.

## A3 Ubuntu 24.04 验收

`a3-acceptance.sh` 是 fail-closed 的 VPS 验收辅助脚本。它只处理明确的
`/etc/s-box` 配置和 systemd 服务路径，不清理用户目录、不刷新防火墙、不改 SSH。

```bash
bash tests/vps/a3-acceptance.sh baseline /tmp/sbyg-a3/baseline.redacted
bash tests/vps/a3-acceptance.sh check /tmp/sbyg-a3/check.redacted
bash tests/vps/a3-acceptance.sh backup /tmp/sbyg-a3/backup-current
bash tests/vps/a3-acceptance.sh rollback /tmp/sbyg-a3/backup-current
```

## A4 核心升级验收

A4 的目标是把核心版本选择和升级回滚变成可重复的维护流程：

1. 默认稳定版本从 sing-box 官方 Releases API 解析，排除 draft/prerelease；下载资产仍必须通过官方 Release digest 校验。
2. `sb` 菜单的稳定版、测试版和指定版本入口共享同一套 API 解析，避免依赖 GitHub HTML 或 jsDelivr 页面正则。
3. systemd 健康 unit 指向发布包内的 `scripts/sb-doctor.sh`，安装、升级后都要手动启动一次 health service 并检查 `Result=success`。
4. 核心升级前后都要运行 `sing-box check`、服务/监听检查和 doctor；失败时用事务快照恢复旧核心与配置。

完整的脱敏结果见 [`a4-core-upgrade-report.md`](a4-core-upgrade-report.md)。服务端监听通过不等于真实外部客户端握手通过；若要宣称端到端通过，必须另行提供实际客户端路径并在不保存订阅密钥的前提下验证。

故障注入必须先使用 `backup` 在 `/tmp/sbyg-a3/<backup>` 保存配置和 unit，再使用明确的
`rollback` 目录恢复。恢复前会校验 `SHA256SUMS`（如存在）并恢复备份中已有的相关 unit；
备份目录必须是新的、明确的子目录，不能把未验证的路径传给恢复命令。
