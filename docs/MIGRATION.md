# 从旧版迁移与回滚

## 迁移前

```bash
sudo install -d -m 700 /var/backups/sing-box-yg
sudo tar -C /etc -czf "/var/backups/sing-box-yg/etc-s-box-$(date +%Y%m%d-%H%M%S).tar.gz" s-box
sudo iptables-save | sudo tee /var/backups/sing-box-yg/iptables.before >/dev/null
sudo ip6tables-save | sudo tee /var/backups/sing-box-yg/ip6tables.before >/dev/null
```

只检查旧规则，不要全局 flush：

```bash
sudo iptables-save | grep -E 'sing-box|SBYG|DNAT'
sudo ip6tables-save | grep -E 'sing-box|SBYG|DNAT'
```

随后按 README 的固定 Release 安装。安装器不会从上游或本 fork 的 `main` 直接执行脚本。迁移后轮换节点 UUID/密码、Reality 私钥、Cloudflare token、订阅 token，并运行：

```bash
sudo /etc/s-box/sing-box check -c /etc/s-box/sb.json
sudo /usr/local/lib/sing-box-yg/scripts/sb-doctor.sh
sudo systemctl status sing-box --no-pager
```

确认旧 DNAT 规则确属本项目后逐条删除；不要删除 SSH、Docker、面板或其他代理的规则。

## 升级与回滚

```bash
sudo /usr/local/lib/sing-box-yg/scripts/install.sh --channel stable --upgrade
sudo /usr/local/lib/sing-box-yg/scripts/install.sh --version vX.Y.Z --upgrade
```

核心/配置更新在锁内完成，候选配置必须通过 `sing-box check`、服务状态和监听检查；失败时恢复上一个配置和核心。若需人工恢复卸载备份，把对应时间目录中的 `/etc/s-box` 恢复后再次校验，不要覆盖其他系统目录。
