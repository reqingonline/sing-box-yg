# A2 兼容性与 Serv00 实施计划

## 1. 资产与 Node 模块边界

- [ ] 新增 `package.json`，声明 CommonJS 且无运行时依赖。
- [ ] 将 `package.json` 纳入 `kp.sh` 远程部署包、Serv00 管理资产、保活脚本同步和清理登记。
- [ ] 为 app 测试增加无 `jq` 的状态 JSON 断言回退，并补充资产声明断言。

## 2. sing-box 配置迁移

- [ ] 将 1.12/1.14 的 DNS 与 HTTP client 补齐逻辑改为按 tag 检查，保持用户已有条目和原子替换。
- [ ] 扩充兼容性 fixture，覆盖已有自定义 DNS/HTTP client 和重复运行。

## 3. Argo 与端口兼容

- [ ] 在两份 Serv00 脚本中加入按 inbound tag 读取端口的受限 helper。
- [ ] 固定/临时 Argo 分支以 token 文件为依据，修复 JWT/特殊字符 token 被误判为临时隧道的问题。
- [ ] 固定 token 输入不回显，并添加静态回归测试，确保没有把 token 放进命令参数。

## 4. 回归与交付

- [ ] 运行 Shell 语法、A2 focused tests、现有 suite 和安全扫描。
- [ ] 提交 A2 分支并推送到 GitHub，记录提交 SHA、测试结果和已知环境跳过项。
