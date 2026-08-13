# sing-box-yg 第一阶段安全与运维修复设计

日期：2026-08-13

## 目标与范围

第一阶段只修复已经在主线审查和 Ubuntu 24.04 验收中确认的高风险问题，目标是让安装失败可见、系统防火墙不被依赖安装破坏、健康检查服务能够真实运行，并且仓库不再携带可复用的 WARP 私钥。

本阶段包含：

1. 安装器 prefix 防护：拒绝 `/` 以及 `/etc`、`/usr`、`/var` 等系统根目录本身，保留默认安装目录、合法的专用子目录和测试用临时目录；拒绝包含 `..` 的未规范化路径。
2. Linux 依赖安装收敛：移除 Debian/Ubuntu 上会替换或删除 UFW 的 `iptables-persistent` 依赖；移除无条件的全系统 `yum update`/`dnf update`；所有包管理、目录创建和 marker 写入操作必须显式失败即退出。
3. 健康服务可靠性：systemd health unit 使用 `StateDirectory=sing-box-yg` 和严格权限，让 systemd 在启动前创建 `/var/lib/sing-box-yg`，避免 namespace 初始化失败。
4. 诊断脚本交付：`scripts/sb-doctor.sh` 在仓库中标记为可执行，并补充直接执行测试。
5. WARP 凭据边界：删除 `sb.sh` 和 `serv00.sh` 中的共享 WireGuard 私钥；只有用户通过环境变量提供完整、格式正确的自有 WARP 凭据时才生成 WARP 出站，否则使用 direct。

本阶段不包含：sing-box beta 默认升级、Argo 上游交互同步、Serv00 全量重构、远程 VPS 验收、GitHub tag/release/push，以及与上述问题无关的重构。

## 设计

### 安装器与 prefix

`scripts/install.sh` 保留现有的绝对路径检查，并增加词法规范化规则：去掉末尾 `/`，拒绝路径段 `..`，拒绝系统根目录列表和根目录本身。检查在下载和移动旧安装目录之前完成，因此错误输入不会创建父目录、替换现有目录或写入 wrapper。

### 依赖与 marker

将 `sb.sh` 的首次依赖安装封装为返回状态的流程。每一个包管理命令、必要目录创建和 `.sbyg-dependencies` 写入都通过 `if ! ...; then` 检查。依赖流程失败时打印明确错误并退出；只有全部步骤成功后才创建 `/etc/s-box` 并写 marker。Debian/Ubuntu 继续安装脚本实际使用的基础包，但不再主动安装 `iptables-persistent`；RHEL 系列只安装脚本依赖，不执行全系统更新。

### health unit

`lib/service.sh` 生成的 oneshot unit 增加 `StateDirectory=sing-box-yg` 和 `StateDirectoryMode=0700`。`ReadWritePaths` 继续限制到配置、状态和运行时目录。这样目录生命周期由 systemd 管理，不在单元渲染函数中对测试环境或宿主机执行额外写入。

### WARP 配置

`sb.sh` 的 WARP 账户注册失败时不再落到仓库内置私钥；可选地读取用户自有的 `SBYG_WARP_PRIVATE_KEY`、`SBYG_WARP_IPV6` 和 `SBYG_WARP_RESERVED`，不完整或格式错误时拒绝生成配置。`serv00.sh` 沿用 `serv00keep.sh` 已有的可选凭据模式，使用 `SBYG_WARP_PRIVATE_KEY`、`SBYG_WARP_LOCAL_IPV4`、`SBYG_WARP_LOCAL_IPV6`、`SBYG_WARP_RESERVED`，缺少完整 tuple 时禁用 WARP 分流并保持 direct 出站。

## 错误处理与回滚

- prefix 校验失败：在任何下载、备份或替换之前退出。
- 依赖失败：不写 marker，不继续进入安装菜单；已有旧 marker 不会被覆盖。
- health unit 渲染失败：保留现有 unit 文件，不执行 enable/restart。
- WARP 凭据缺失或无效：不写 WARP 出站和分流规则；普通 direct 路由仍可生成。账户注册失败时返回失败状态，不使用共享凭据。
- 本阶段不修改远程机器；远程验收安排在第二阶段，避免本地修复未通过时影响节点。

## 验证计划

1. `bash -n` 检查所有变更 shell 文件。
2. installer unit：合法临时 prefix 安装成功；`/`、`/etc`、`/usr`、`/var`、含 `..` 的路径在副作用前拒绝。
3. dependency unit：静态确认不再安装 `iptables-persistent` 或执行全系统 yum/dnf update；注入包安装失败时 marker 不存在。
4. service unit：生成结果包含 `StateDirectory`、权限和 health timer 配置。
5. doctor unit：脚本可直接执行，输出继续脱敏。
6. owned-updates unit：`sb.sh`、`serv00.sh`、`serv00keep.sh` 不包含可复用的固定 WARP 私钥，并保留用户自有凭据路径。
7. 运行仓库现有测试套件；对因本机缺少 `jq` 或运行时依赖而跳过/失败的项目单独记录，不把环境问题误报为代码通过。
