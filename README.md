# Free WAF Threat Intelligence Sync 0.1.0

旧版宝塔第三方免费 `free_waf` 的 IPv4 情报同步器。仅使用 Python 标准库，不安装 pip 依赖。默认命令为模拟模式；只有 `--apply` 才会写入 `ip_black.json` 并在 `nginx -t` 通过后执行平滑 reload。

## 当前适配目标

- 黑名单：`/www/server/free_waf/rule/ip_black.json`
- 白名单：`/www/server/free_waf/rule/ip_white.json`（只读）
- Lua 读取：`/www/server/free_waf/init.lua` 初始化阶段读入内存
- JSON：`[[起始IPv4四字节数组, 结束IPv4四字节数组], ...]`

## 情报源

- IPsum Level 4：IP 出现在至少 4 个公开名单；每天更新。
- FireHOL Level 2：聚合近约 48 小时攻击名单，包含 Blocklist.de、DShield 1d、GreenSnow 等。
- Feodo Tracker Recommended：恶意软件 C2 推荐名单（配置中默认关闭；本次核验到的名单时间戳较旧，确认上游恢复新鲜更新后再手动启用）。
- Spamhaus DROP：高危恶意网段，使用官方 `drop_v4.json`，每天抓取一次。

默认不会使用 FireHOL Level 1，因为它含有大量特殊网段/全局网段，不适合直接导入逐条匹配的旧版 WAF。Feodo 当前默认关闭，避免依赖本次核验时显示旧时间戳的名单。

## 安全策略

- 仅处理 IPv4；旧 WAF 的 `compare_ip()` 明确跳过 IPv6。
- 只接受全局可路由 IPv4。
- 默认拒绝宽于 `/20` 的网段，避免误封过大的地址块。
- 外部名单与 WAF 白名单重叠的 IP 会被从外部名单中剔除。
- 保留初始黑名单及之后在 WAF 文件中手工新增的记录；通过状态文件区分同步器规则与人工规则。
- 只在 `--apply` 时写入；写入前备份；先 `nginx -t`，再 `nginx -s reload`；失败自动恢复。
- 同步器有并发锁；下载失败时使用有效期内的旧缓存；必需源没有有效数据则拒绝应用。
- 默认自动情报规则上限 25,000 条，防止旧 Lua 的 `ipairs()` 逐条匹配变得过重。

这不是“全球所有攻击 IP”的完整名单；任何公开情报源都有覆盖范围和误报。应先运行模拟模式检查报告。

## 部署（Debian / Ubuntu / 宝塔）

以 root 执行：

```bash
mkdir -p /opt/free-waf-threat-sync /etc/free-waf-threat-sync
```

把 `free_waf_threat_sync.py` 上传到 `/opt/free-waf-threat-sync/`，把 `config.example.json` 上传到 `/etc/free-waf-threat-sync/config.json`，然后：

```bash
chmod 750 /opt/free-waf-threat-sync/free_waf_threat_sync.py
chmod 600 /etc/free-waf-threat-sync/config.json
python3 /opt/free-waf-threat-sync/free_waf_threat_sync.py --self-test
python3 /opt/free-waf-threat-sync/free_waf_threat_sync.py --config /etc/free-waf-threat-sync/config.json
```

最后一条是模拟运行，不会改动 WAF。

确认预览报告符合预期后，手动正式应用：

```bash
python3 /opt/free-waf-threat-sync/free_waf_threat_sync.py --config /etc/free-waf-threat-sync/config.json --apply
```

查看状态：

```bash
python3 /opt/free-waf-threat-sync/free_waf_threat_sync.py --config /etc/free-waf-threat-sync/config.json --status
```

回滚到上一次同步前的黑名单：

```bash
python3 /opt/free-waf-threat-sync/free_waf_threat_sync.py --config /etc/free-waf-threat-sync/config.json --rollback
```

## 开启每 30 分钟自动同步（可选）

把 `systemd/free-waf-threat-sync.service` 和 `.timer` 上传到 `/etc/systemd/system/`，然后：

```bash
systemctl daemon-reload
systemctl enable --now free-waf-threat-sync.timer
systemctl list-timers free-waf-threat-sync.timer
journalctl -u free-waf-threat-sync.service -n 100 --no-pager
```

注意：自动任务会执行正式应用。建议先至少完成一次人工模拟和人工 `--apply`，确认运行正常后再启用 timer。

## 重要注意

- 不要把 `ip_white.json` 交给同步器写入；本程序只读它。
- 初次运行时，当前 `ip_black.json` 内的所有规则都会作为人工规则保留。
- `protected_ips` 可填额外的管理出口 IP 或网段，例如 `203.0.113.10/32`（请换成自己的真实地址）。
- 如果你的网站前面有反向代理/CDN，必须先确认 WAF 读取到的真实客户端 IP，否则任何 IP 黑名单都会失去准确性；当前脚本不会改动真实 IP 获取配置。
- 当前脚本按你提供的 Lua 逻辑只生成 IPv4 规则，不生成 IPv6 规则。
