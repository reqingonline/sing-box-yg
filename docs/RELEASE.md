# 发布与上游同步

## 同步上游

1. 获取 upstream，但不要直接合并或执行其下载 URL。
2. 审阅脚本、二进制、工作流权限、删除/防火墙范围和配置 schema 变化。
3. 选择 cherry-pick 或在本 fork 重新实现；所有可执行下载必须来自可信 Release 并有 SHA-256。
4. 更新 1.13/1.14 兼容 fixture，运行 `bash scripts/release-checks.sh` 和发行版矩阵。

## 创建发布

```bash
git status --short
bash scripts/release-checks.sh
git tag -s vX.Y.Z -m 'vX.Y.Z'
git push origin vX.Y.Z
```

`Verified release` 工作流仅在 `v*` 标签运行，权限限定为该 job 的 `contents: write`。它用 `git archive` 与 `gzip -n` 创建确定性源码包，生成并在新目录复核 `SHA256SUMS`，然后发布资产。

发布后重新下载两个资产并执行：

```bash
grep ' sing-box-yg-vX.Y.Z.tar.gz$' SHA256SUMS | sha256sum -c -
tar -tzf sing-box-yg-vX.Y.Z.tar.gz >/dev/null
```

不要上传生成的节点配置、订阅、token、测试 VPS 原始日志或包含真实地址的诊断文件。`main` 是开发通道，必须显式选择，不作为生产安装来源。
