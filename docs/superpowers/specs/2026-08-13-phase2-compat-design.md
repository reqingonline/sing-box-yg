# A2 兼容性与 Serv00 维护设计

## 背景

A1 已经把安装来源、依赖失败、服务状态目录、诊断入口和 WARP 凭据边界收紧。A2 只处理已确认会影响长期维护的兼容性问题，不把上游 `serv00.sh` 的整段破坏性改写直接同步进来。

## 目标

1. Serv00 保活页的 Node 入口明确声明 CommonJS，不受部署目录上层 `package.json` 的 `type` 影响；更新、远程部署和清理路径都必须同步这个声明文件。
2. sing-box 1.14+ 配置迁移在保留用户已有 DNS、HTTP client 和 rule-set 的同时，补齐可引用的 `local` DNS 与 `direct` HTTP client，避免“字段存在但引用不存在”的无效配置。
3. Argo 固定隧道的判断以受保护的 token 文件为准，而不是用过窄的 token 正则猜测；临时隧道始终回落到当前 `vmess-sb` 的端口。Argo 端口按标签读取，避免未来调整 inbound 顺序后连错端口。
4. 测试在没有 `jq` 的开发机上给出明确的降级/跳过结果；有 `jq` 的 CI 仍执行完整 JSON 断言。

## 非目标

- 不升级到 sing-box beta，也不修改默认稳定通道。
- 不整体同步上游 `serv00.sh`；上游当前版本包含宽泛清理、未校验远程下载和凭据输出等与本仓库安全边界冲突的行为。
- 不改变现有菜单编号、协议组合、订阅路径或默认监听范围。

## 设计

### Serv00 Node 入口

在仓库根目录加入仅包含 `private`、`type: commonjs` 的 `package.json`。`kp.sh`、`serv00.sh`、`serv00keep.sh` 以及资产清单将它与 `app.js` 一起复制、登记和更新。这样既保持现有 `app.js` 路径，又不依赖宿主机的模块默认值。

### 配置迁移

1.10/1.11 只做 JSON 校验和原子复制。1.12+ 保证存在 `dns.servers` 中的 `local`；1.14+ 额外保证 `http_clients` 中的 `direct` 和 `route.default_http_client`，并把远程 rule-set 的旧 `download_detour` 一次性迁移为 `http_client`。用户已经定义的同名条目不重复追加。

### Argo

保留现有固定/临时选择。固定模式只在 `ARGO_AUTH.log` 非空时启用 `tunnel ... run`，token 继续通过受保护文件注入 `TUNNEL_TOKEN`；临时模式使用 `tunnel --url http://localhost:<vmess-sb port>`。固定域名和 token 不在终端回显。读取配置端口使用唯一 tag，而不是数组下标。

## 验收

- `bash -n` 覆盖所有修改的 Shell 文件。
- Serv00 app 测试在当前 Windows/Git Bash（无 `jq`）可运行；有 `jq` 时继续验证 JSON 字段。
- 配置兼容测试覆盖已有自定义项、1.14 `http_clients`、rule-set 字段迁移和幂等性。
- 所有现有单元/集成测试、`git diff --check` 通过；环境缺少 `jq` 的测试只允许明确 `SKIP`，不能静默通过。
