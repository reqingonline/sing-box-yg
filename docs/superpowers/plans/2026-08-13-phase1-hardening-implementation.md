# sing-box-yg 第一阶段安全与运维修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 修复安装器 prefix、依赖失败、health 状态目录、doctor 权限和共享 WARP 私钥问题，完成本地验证后推送独立 GitHub 分支。

**Architecture:** 保持现有脚本结构，不做无关重构。安装器在副作用前校验路径；sb.sh 的依赖流程显式返回失败并只在成功后写 marker；systemd 用 StateDirectory 管理健康检查状态目录；WARP 缺省走 direct，只有用户自有凭据完整时才启用。

**Tech Stack:** Bash、systemd unit、Git、现有 Bash 测试套件。

---

### Task 1: 安装器 prefix 安全边界

**Files:** scripts/install.sh lines 61-65; tests/unit/test_installer.sh.

- [ ] Step 1: 在 installer 测试中加入 assert_prefix_rejected 函数，依次验证 /、/etc、/usr、/var、/tmp/../etc 被 --dry-run 拒绝，并验证带末尾斜杠的临时专用目录仍被接受。
- [ ] Step 2: 运行 bash tests/unit/test_installer.sh，确认旧实现至少有一个 unsafe prefix 失败。
- [ ] Step 3: 在 scripts/install.sh 的绝对路径检查处加入以下校验：

~~~bash
case $prefix in
  /*) ;;
  *) die 'prefix must be an absolute path' ;;
esac
prefix=${prefix%/}
[ -n "$prefix" ] || prefix=/
case "/$prefix/" in
  */../*) die 'prefix must not contain .. path segments' ;;
esac
case "$prefix" in
  /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
    die 'prefix must be a dedicated directory below a system root'
    ;;
esac
~~~

检查必须早于下载、创建 parent 和移动旧目录；/tmp/install、/etc/s-box、默认目录必须保留。
- [ ] Step 4: 运行 bash tests/unit/test_installer.sh，预期输出 verified installer: PASS。
- [ ] Step 5: 提交 fix: reject unsafe installer prefixes，并运行 git diff --cached --check。

### Task 2: 依赖安装失败安全与 UFW 兼容

**Files:** sb.sh lines 87-154; tests/unit/test_dependency_marker.sh; tests/unit/test_firewall_chain.sh.

- [ ] Step 1: 在 dependency marker 测试中增加静态断言：sb.sh 不得出现 iptables-persistent、yum update 或 dnf update；必须出现 dependency_install_status 和 dependency marker was not written。
- [ ] Step 2: 将 sb.sh 首次依赖代码封装成 sbyg_install_dependencies。apt 分支只安装 jq、cron、socat、busybox、coreutils、util-linux，不安装 iptables-persistent；yum/dnf 分支只安装脚本依赖，不执行 update -y；apk、apt、yum、dnf 和逐包补装都在失败时 return 1。
- [ ] Step 3: 用下面的尾部控制 marker 写入，替代当前无条件 touch：

~~~bash
dependency_install_status=0
if [ ! -f "$dependency_marker" ]; then
  green '首次安装 Sing-box-yg 脚本必要的依赖……'
  sbyg_install_dependencies || dependency_install_status=$?
  if [ "$dependency_install_status" -ne 0 ]; then
    red '依赖安装失败，dependency marker was not written'
    exit "$dependency_install_status"
  fi
  mkdir -p /etc/s-box || exit 1
  touch "$dependency_marker" || {
    red 'dependency marker 写入失败'
    exit 1
  }
fi
~~~

- [ ] Step 4: 增加隔离 fake apt-get failure-injection 测试；update 返回 1 时断言非零退出且临时 marker 不存在。若入口必须 root，明确输出 SKIP，不伪报通过。
- [ ] Step 5: 运行两个 focused tests，确认静态危险命令无命中，然后提交 fix: fail closed during dependency bootstrap。

### Task 3: health service 状态目录

**Files:** lib/service.sh lines 109-123; tests/unit/test_service_definition.sh; tests/vps/sing-box-yg-health.service.

- [ ] Step 1: 先在 unit test 增加 StateDirectory=sing-box-yg 和 StateDirectoryMode=0700 的 grep 断言并运行，确认旧实现失败。
- [ ] Step 2: 在 lib/service.sh 的 health service unit 中、ProtectSystem=strict 后加入：

~~~ini
StateDirectory=sing-box-yg
StateDirectoryMode=0700
~~~

保留现有 ReadWritePaths。
- [ ] Step 3: 在 tests/vps/sing-box-yg-health.service fixture 加入同样两行。
- [ ] Step 4: 运行 bash tests/unit/test_service_definition.sh，预期 hardened service definition: PASS。
- [ ] Step 5: 提交 fix: create health service state directory。

### Task 4: doctor 可执行权限

**Files:** scripts/sb-doctor.sh mode; tests/unit/test_doctor.sh.

- [ ] Step 1: 在 test_doctor.sh 开头加入 test -x "$repo_root/scripts/sb-doctor.sh" 断言，先确认旧权限失败。
- [ ] Step 2: 执行 git update-index --chmod=+x scripts/sb-doctor.sh，不改脚本内容。
- [ ] Step 3: 运行 bash tests/unit/test_doctor.sh，预期 redacted doctor: PASS。
- [ ] Step 4: 提交 fix: ship doctor as executable。

### Task 5: 移除共享 WARP 私钥

**Files:** sb.sh lines 3509-3558; serv00.sh lines 485-656; tests/unit/test_owned_updates.sh.

- [ ] Step 1: 在 owned updates 测试中对 sb.sh、serv00.sh、serv00keep.sh 扫描固定 private_key 和 pvk base64 字符串，并断言 sb.sh、serv00.sh 都保留 SBYG_WARP_PRIVATE_KEY 路径。
- [ ] Step 2: 替换 sb.sh 固定 pvk/v6/res fallback：Cloudflare 注册失败时，只有 SBYG_WARP_PRIVATE_KEY、SBYG_WARP_IPV6、SBYG_WARP_RESERVED 都非空才使用用户凭据，否则打印拒绝共享私钥并 return 1。
- [ ] Step 3: 将 serv00keep.sh 已验证的 optional WARP tuple 模式移植到 serv00.sh。SBYG_WARP_PRIVATE_KEY 必须匹配 43 字符 base64 加等号；IPv4、IPv6 和三个 0-255 reserved 字节必须通过校验；完整 tuple 才生成 wg 出站和 jnn-pa.googleapis.com 分流，否则只生成 direct，不能留下悬空 wg tag。
- [ ] Step 4: 运行 bash tests/unit/test_owned_updates.sh 和 bash -n sb.sh serv00.sh serv00keep.sh，预期无固定 key 命中、语法通过。
- [ ] Step 5: 提交 fix: remove shared WARP private keys。

### Task 6: 汇总回归、审计与 GitHub 分支提交

**Files:** all tracked files for verification; no additional implementation files.

- [ ] Step 1: 依次运行 tests/unit/test_installer.sh、test_dependency_marker.sh、test_service_definition.sh、test_doctor.sh、test_owned_updates.sh，并对 git ls-files '*.sh' 全部执行 bash -n。
- [ ] Step 2: 运行 bash tests/run.sh，记录通过、失败和环境 skip；缺少 jq 等环境问题不得伪报通过。
- [ ] Step 3: 运行 git diff --check、git status --short，并用 git grep 搜索已知两个固定私钥字符串，预期无输出。
- [ ] Step 4: 审查 git diff origin/main...HEAD --stat、git log origin/main..HEAD 和 git diff origin/main...HEAD --check，确认无 A2、release tag 或生产 VPS 变更。
- [ ] Step 5: 只执行 git push --set-upstream origin maintenance/phase1-hardening；不 force push、不直接推 main。记录远端分支、HEAD SHA 和测试摘要。
