# 发布与上游同步

## 同步上游

1. 获取 upstream，但不要直接合并或执行其下载 URL。
2. 审阅脚本、二进制、工作流权限、删除/防火墙范围和配置 schema 变化。
3. 选择 cherry-pick 或在本 fork 重新实现；所有可执行下载必须来自可信 Release 并有 SHA-256。
4. 更新 1.13/1.14 兼容 fixture，运行 `bash scripts/release-checks.sh` 和发行版矩阵。

## 创建发布

默认发布流程不依赖维护者本机保存长期 GitHub token：

1. 在发布 PR 中把根目录 `RELEASE_VERSION` 更新为新的 `vX.Y.Z`。
2. 运行 `bash scripts/release-checks.sh`，提交并合并 PR。
3. `Verified release` 工作流先验证发布提交属于远端 `main` 历史，再创建或核对指向该提交的 Release tag，生成确定性源码包和 `SHA256SUMS`，最后原子发布 Release 与资产。
4. 工作流可以安全重跑：已有标签必须仍指向同一提交，已有 Release 资产会校验后覆盖。

如果维护者已配置签名密钥，也可以手动创建签名标签；标签必须与 `RELEASE_VERSION` 完全一致：

```bash
bash scripts/release-checks.sh
git tag -s vX.Y.Z -m 'vX.Y.Z'
git push origin vX.Y.Z
```

`Verified release` 的默认权限为 `contents: read`，只有发布 job 使用 `contents: write`。它会在创建标签前完成安全预检，并用 `git archive` 与 `gzip -n` 创建确定性源码包。

发布后重新下载两个资产并执行：

```bash
grep ' sing-box-yg-vX.Y.Z.tar.gz$' SHA256SUMS | sha256sum -c -
tar -tzf sing-box-yg-vX.Y.Z.tar.gz >/dev/null
```

不要上传生成的节点配置、订阅、token、测试 VPS 原始日志或包含真实地址的诊断文件。`main` 是开发通道，必须显式选择，不作为生产安装来源。

更新 Serv00 的 `sb` 或 `server` 依赖时，必须在隔离主机完整下载资产、核对来源并更新 `serv00-assets.sha256`，随后运行安全预检。不得因为上游 Release 的 `digest` 为空而跳过校验。
