# Free WAF Threat Intelligence Sync 一键安装脚本

适用于旧版宝塔第三方免费 `free_waf`，目标环境为 Debian / Ubuntu / 其他使用 systemd 的 Linux；要求 Python 3.6.8 或更高版本。安装程序会下载并校验 GitHub Release `v0.1.1`，不需要 pip 依赖。

## 一键安装并在检查通过后启用自动同步

以 root 登录服务器执行：

```bash
curl -fsSL -o /root/install-free-waf.sh https://raw.githubusercontent.com/719729765/Free-WAF-Threat-Intelligence-Sync/main/install.sh && bash /root/install-free-waf.sh --yes
```

脚本会：

1. 检查 root、systemd、Python 3.6.8、宝塔 `free_waf` 黑白名单文件和 Nginx 路径。
2. 下载官方 `v0.1.1` Release ZIP，并验证固定 SHA256。
3. 备份旧程序、配置和 systemd 单元文件。
4. 安装程序及 systemd 服务/定时器。
5. 已存在的 `config.json`、状态缓存、WAF 黑名单和白名单均予以保留；首次安装采用 IPsum Level 5 + Spamhaus 的保守预设，默认关闭 FireHOL Level 2。
6. 执行自检和模拟采集；模拟阶段不会修改 WAF。
7. `--yes` 在自检及模拟通过后启用每 30 分钟运行的正式同步定时器。

**注意：** 定时服务执行的是 `--apply`。开启后会根据情报更新 `ip_black.json`，并在名单确实变化、`nginx -t` 通过时平滑 reload Nginx。`ip_white.json` 始终只读。首次启动后，systemd 可能因 `OnBootSec=5min` 已到期而很快触发一次正式同步。

## 交互式安装

不带 `--yes` 时，安装器先运行模拟并显示采集结果，再询问是否开启自动同步：

```bash
bash /root/install-free-waf.sh
```

只安装和模拟、不启用自动任务：

```bash
bash /root/install-free-waf.sh --no-timer
```

## 日常管理

```bash
# 状态与最近日志
bash /root/install-free-waf.sh --status

# 开启自动同步（会启用正式 --apply 定时任务）
bash /root/install-free-waf.sh --start

# 停止并禁用自动同步（不会删除现有黑名单）
bash /root/install-free-waf.sh --stop

# 只移除 systemd 自动任务；保留程序、配置、状态及备份
bash /root/install-free-waf.sh --uninstall
```

## 文件位置

- 程序：`/opt/free-waf-threat-sync/free_waf_threat_sync.py`
- 配置：`/etc/free-waf-threat-sync/config.json`
- 状态：`/var/lib/free-waf-threat-sync/state.json`
- 日志：`/var/log/free-waf-threat-sync/sync.log`
- systemd：`/etc/systemd/system/free-waf-threat-sync.service` 和 `.timer`
- 安装前备份：`/var/backups/free-waf-threat-sync-installer/`
- WAF 黑名单：`/www/server/free_waf/rule/ip_black.json`
- WAF 白名单：`/www/server/free_waf/rule/ip_white.json`（只读）

脚本不会覆盖已有配置，不会清空或重建现有黑名单，不会写入白名单。升级时会备份旧程序及 systemd 单元文件。
