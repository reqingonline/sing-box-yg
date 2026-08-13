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
```

故障注入必须先在 `/tmp/sbyg-a3/<backup>` 保存配置和 unit，再使用明确的
`rollback` 目录恢复；不能把未验证的路径传给恢复命令。
