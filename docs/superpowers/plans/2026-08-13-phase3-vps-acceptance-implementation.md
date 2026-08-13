# A3 Ubuntu 24.04 VPS 验收 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在用户提供的 Ubuntu 24.04 测试 VPS 上完成可恢复的 sing-box-yg 安装、服务、端口、配置和故障回滚验收，并提交脱敏证据。

**Architecture:** 先建立只读基线，再按“上传固定分支内容 → 备份 → 检查/安装 → 服务验收 → 临时故障注入 → 恢复复核”的顺序执行。远程脚本使用显式绝对路径和临时工作目录，任何失败都停止后续变更。

**Tech Stack:** Windows OpenSSH/Tcl expect、Ubuntu 24.04、Bash、systemd、sing-box、jq、Git。

---

### Task 1: 本地准备与脱敏验收工具

**Files:**
- Create: `tests/vps/a3-acceptance.sh`
- Modify: `tests/vps/README.md`
- Test: `bash -n tests/vps/a3-acceptance.sh`

- [ ] **Step 1: 写入只读/可恢复验收脚本**

脚本只接受显式的 `--baseline`、`--check`、`--rollback` 子命令；默认拒绝执行。脚本使用 `/etc/s-box/sb.json`、`/etc/s-box/sing-box` 和 `sing-box.service`，若路径不存在只报告并返回非零，不猜测其他目录。

- [ ] **Step 2: 运行 Shell 语法检查**

Run: `bash -n tests/vps/a3-acceptance.sh`

Expected: exit 0。

- [ ] **Step 3: 提交本地 A3 验收工具**

Run: `git add tests/vps/a3-acceptance.sh tests/vps/README.md && git diff --cached --check && git commit -m "test: add VPS phase three acceptance helper"`

### Task 2: 采集 VPS 基线

**Files:**
- Remote output: `/tmp/sbyg-a3/baseline.redacted`
- Local evidence: `tests/vps/a3-acceptance-report.md`

- [ ] **Step 1: 只读确认系统和仓库状态**

采集 `id -u`、`/etc/os-release`、`uname -m`、磁盘、内存、`systemctl` 状态、`ss` 监听、`ufw`/nftables 摘要、`/etc/s-box` 文件名/权限和当前核心版本；不输出配置正文。

- [ ] **Step 2: 保存基线摘要**

使用 `umask 077` 写入临时目录，只保留路径、权限、哈希、版本和布尔状态，排除密码、Token、UUID、私钥与订阅正文。

### Task 3: 安装/配置/服务验收

**Files:**
- Remote backup: `/tmp/sbyg-a3/backup-<timestamp>/`
- Local evidence: `tests/vps/a3-acceptance-report.md`

- [ ] **Step 1: 创建备份并验证备份可读**

在任何写操作前复制 `/etc/s-box/sb.json`、模板、systemd unit 和 release marker 到权限为 0700 的临时备份目录，并记录 SHA-256。

- [ ] **Step 2: 运行本仓库安装/更新的 dry-run 或固定路径检查**

优先运行现有安装器的 `--dry-run`/版本校验；只有目标路径为空或确认属于本项目时才执行项目级安装，不使用 `curl | bash`。

- [ ] **Step 3: 验证核心、配置和 systemd**

执行核心 `version`、`check -c`、`systemctl is-active sing-box`、健康 timer 状态、unit 安全字段、配置/凭据权限和预期监听端口；记录退出码和脱敏摘要。

### Task 4: 可恢复故障注入与复核

**Files:**
- Remote temporary file: `/tmp/sbyg-a3/invalid.json`
- Local evidence: `tests/vps/a3-acceptance-report.md`

- [ ] **Step 1: 复制当前配置并确认服务健康**

记录原配置哈希，先运行 `sing-box check` 和 `systemctl is-active`，任一失败则停止注入。

- [ ] **Step 2: 注入临时无效配置并测试拒绝**

只写入临时路径，不覆盖正式配置；调用现有 restart/recovery 入口或等价的 `check` 守卫，确认命令非零且正式配置哈希不变。

- [ ] **Step 3: 恢复并复核**

确认服务重新 active、核心 check 成功、监听端口恢复、正式配置哈希与注入前一致；清理仅限 `/tmp/sbyg-a3`。

### Task 5: 交付

**Files:**
- Create: `tests/vps/a3-acceptance-report.md`
- Modify: `docs/superpowers/plans/2026-08-13-phase3-vps-acceptance-implementation.md`

- [ ] **Step 1: 编写脱敏报告**

报告记录测试时间、系统/架构、核心版本、检查命令退出码、端口数量/标签摘要、故障注入与恢复结果、未完成项目；不写 IP、密码、Token、UUID、私钥和完整订阅 URL。

- [ ] **Step 2: 最终验证并提交 A3**

Run: `bash tests/run.sh`、`bash -n tests/vps/*.sh`、`git diff --check`、`git status --short`

Expected: 本地测试无新增失败；VPS 结果与报告一致；工作树干净。

- [ ] **Step 3: 推送但不合并 main**

Run: `git push -u origin maintenance/phase3-vps-acceptance`

Expected: GitHub 新增 A3 分支，记录远端分支和 HEAD SHA。
