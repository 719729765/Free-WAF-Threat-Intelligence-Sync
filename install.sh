#!/usr/bin/env bash
# Free WAF Threat Intelligence Sync - one-click installer
# Target: Debian/Ubuntu/BaoTa free_waf, Python 3.6.8+, systemd
set -Eeuo pipefail

VERSION="v0.1.1"
REPO="719729765/Free-WAF-Threat-Intelligence-Sync"
ASSET="free_waf_threat_sync_0.1.1.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
EXPECTED_SHA256="4be62d7e7e1acce68b1b386d8397145f7192ec9f438ee40691a6184487574030"

APP_DIR="/opt/free-waf-threat-sync"
ETC_DIR="/etc/free-waf-threat-sync"
CONFIG="${ETC_DIR}/config.json"
APP="${APP_DIR}/free_waf_threat_sync.py"
SERVICE="/etc/systemd/system/free-waf-threat-sync.service"
TIMER="/etc/systemd/system/free-waf-threat-sync.timer"
WAF_DIR="/www/server/free_waf/rule"
BLACKLIST="${WAF_DIR}/ip_black.json"
WHITELIST="${WAF_DIR}/ip_white.json"
BACKUP_ROOT="/var/backups/free-waf-threat-sync-installer"
UNIT_NAME="free-waf-threat-sync"

AUTO_YES=0
NO_TIMER=0
ACTION="install"

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; RESET='\033[0m'
log()  { printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}[OK]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[注意]${RESET} %s\n" "$*"; }
err()  { printf "${RED}[错误]${RESET} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat <<'EOF'
Free WAF Threat Intelligence Sync 一键安装/启动脚本

用法：
  bash install.sh                 安装/更新，完成自检和模拟，再询问是否启用定时同步
  bash install.sh --yes           安装/更新并在检查通过后自动启用每30分钟定时同步
  bash install.sh --no-timer      只安装、检测和模拟，不启用定时任务
  bash install.sh --status        查看同步器状态、定时器状态和最近日志
  bash install.sh --start         启用并启动定时任务（会执行正式同步）
  bash install.sh --stop          停止并禁用定时任务
  bash install.sh --uninstall     仅移除 systemd 自动任务；保留程序、配置、状态和备份
  bash install.sh --help          显示帮助

说明：自动任务执行正式应用，会更新 free_waf 黑名单；白名单保持只读。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) AUTO_YES=1 ;;
    --no-timer) NO_TIMER=1 ;;
    --status) ACTION="status" ;;
    --start) ACTION="start" ;;
    --stop) ACTION="stop" ;;
    --uninstall) ACTION="uninstall" ;;
    --help|-h) usage; exit 0 ;;
    *) die "未知参数：$1（使用 --help 查看用法）" ;;
  esac
  shift
done

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "请使用 root 账号运行：sudo bash install.sh"
}

require_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "未发现 systemctl；本脚本需要 systemd。"
  [[ -d /run/systemd/system ]] || die "当前环境未运行 systemd（缺少 /run/systemd/system），无法启用自动任务。"
}

status_action() {
  require_root
  if [[ -x "$APP" && -f "$CONFIG" ]]; then
    "$PYTHON3" "$APP" --config "$CONFIG" --status || true
  else
    warn "同步器主程序或配置尚未安装。"
  fi
  echo
  systemctl status "${UNIT_NAME}.timer" --no-pager -l 2>/dev/null || true
  echo
  journalctl -u "${UNIT_NAME}.service" -n 30 --no-pager 2>/dev/null || true
}

if [[ "$ACTION" == "status" || "$ACTION" == "start" || "$ACTION" == "stop" || "$ACTION" == "uninstall" ]]; then
  require_root
  PYTHON3="$(command -v python3 || true)"
  if [[ "$ACTION" == "status" ]]; then
    [[ -n "$PYTHON3" ]] || die "未找到 python3。"
    status_action
    exit 0
  elif [[ "$ACTION" == "start" ]]; then
    require_systemd
    systemctl enable --now "${UNIT_NAME}.timer"
    ok "自动同步定时器已启用。注意：它会在下一次触发时正式更新 WAF 黑名单。"
    systemctl list-timers --all | grep -F "$UNIT_NAME" || true
    exit 0
  elif [[ "$ACTION" == "stop" ]]; then
    require_systemd
    systemctl disable --now "${UNIT_NAME}.timer" || true
    ok "自动同步已停止并禁用；现有黑名单不会被删除。"
    exit 0
  elif [[ "$ACTION" == "uninstall" ]]; then
    require_systemd
    systemctl disable --now "${UNIT_NAME}.timer" 2>/dev/null || true
    if systemctl is-active --quiet "${UNIT_NAME}.service"; then
      die "同步服务正在执行。定时器已禁用；请等待当前任务结束后重新运行 --uninstall。"
    fi
    rm -f "$SERVICE" "$TIMER"
    systemctl daemon-reload
    systemctl reset-failed "${UNIT_NAME}.service" "${UNIT_NAME}.timer" 2>/dev/null || true
    warn "已移除自动任务。程序、配置、同步状态、WAF 黑名单、白名单和备份均予以保留。"
    exit 0
  fi
fi

require_root
require_systemd

PYTHON3="$(command -v python3 || true)"
[[ -n "$PYTHON3" ]] || die "未找到 python3。请先安装 Python 3.6.8 或更高版本。"
PYTHON3="$(readlink -f "$PYTHON3" 2>/dev/null || echo "$PYTHON3")"
"$PYTHON3" - <<'PY' || exit 1
import sys
if sys.version_info < (3, 6, 8):
    sys.stderr.write("需要 Python 3.6.8 或更高版本，当前为 %s\n" % sys.version.split()[0])
    sys.exit(1)
print("Python 版本检查通过：%s" % sys.version.split()[0])
PY

[[ -d "$WAF_DIR" ]] || die "未发现旧版宝塔 free_waf 目录：$WAF_DIR\n本脚本不会在不匹配的服务器上盲目安装。"
[[ -f "$BLACKLIST" ]] || die "未发现黑名单文件：$BLACKLIST"
[[ -f "$WHITELIST" ]] || die "未发现白名单文件：$WHITELIST"
[[ -x /www/server/nginx/sbin/nginx ]] || die "未发现宝塔 Nginx：/www/server/nginx/sbin/nginx"
command -v sha256sum >/dev/null 2>&1 || die "缺少 sha256sum 命令。"

if [[ "$NO_TIMER" -eq 1 && "$AUTO_YES" -eq 1 ]]; then
  die "--yes 与 --no-timer 不能同时使用。"
fi

TMP_DIR="$(mktemp -d /tmp/free-waf-install.XXXXXX)"
ZIP_PATH="${TMP_DIR}/${ASSET}"
EXTRACT_DIR="${TMP_DIR}/extract"
mkdir -p "$EXTRACT_DIR"

BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

OLD_APP=0; OLD_CONFIG=0; OLD_SERVICE=0; OLD_TIMER=0
WAS_TIMER_ACTIVE=0; WAS_TIMER_ENABLED=0
MUTATION_STARTED=0

backup_file() {
  local src="$1" name="$2"
  if [[ -e "$src" ]]; then
    cp -a "$src" "${BACKUP_DIR}/${name}"
    return 0
  fi
  return 1
}

restore_one() {
  local saved="$1" target="$2" existed="$3"
  if [[ "$existed" -eq 1 && -e "$saved" ]]; then
    cp -a "$saved" "$target"
  else
    rm -f "$target"
  fi
}

rollback_install() {
  warn "安装检测失败，正在恢复安装前的程序和 systemd 文件……"
  restore_one "${BACKUP_DIR}/free_waf_threat_sync.py" "$APP" "$OLD_APP"
  restore_one "${BACKUP_DIR}/config.json" "$CONFIG" "$OLD_CONFIG"
  restore_one "${BACKUP_DIR}/free-waf-threat-sync.service" "$SERVICE" "$OLD_SERVICE"
  restore_one "${BACKUP_DIR}/free-waf-threat-sync.timer" "$TIMER" "$OLD_TIMER"
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [[ "$WAS_TIMER_ACTIVE" -eq 1 ]]; then
    systemctl start "${UNIT_NAME}.timer" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}

cleanup() { [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
on_error() {
  local rc="$1"
  trap - ERR
  if [[ "${MUTATION_STARTED:-0}" -eq 1 ]]; then
    rollback_install
  fi
  err "安装过程中出现错误（退出码 ${rc}）。"
  exit "$rc"
}
trap cleanup EXIT
trap 'on_error "$?"' ERR

log "检查到目标：旧版宝塔 free_waf"
log "黑名单：$BLACKLIST"
log "白名单：$WHITELIST（只读，不会被安装器修改）"
log "正在下载官方 Release ${VERSION}……"

if command -v curl >/dev/null 2>&1; then
  curl -fL --connect-timeout 20 --max-time 600 --retry 3 --retry-delay 2 \
    -A "Free-WAF-Installer/${VERSION}" -o "$ZIP_PATH" "$DOWNLOAD_URL" \
    || die "下载失败。请检查服务器能否访问 GitHub Release。"
elif command -v wget >/dev/null 2>&1; then
  wget -q --timeout=30 --tries=3 -O "$ZIP_PATH" "$DOWNLOAD_URL" \
    || die "下载失败。请检查服务器能否访问 GitHub Release。"
else
  die "缺少 curl 或 wget，请安装其中一个后重试。"
fi

ACTUAL_SHA256="$(sha256sum "$ZIP_PATH" | awk '{print $1}')"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || die "安装包 SHA256 校验失败！期望：$EXPECTED_SHA256；实际：$ACTUAL_SHA256。为安全起见已停止。"
ok "Release 安装包 SHA256 校验通过。"

log "正在安全解压并检查安装包……"
"$PYTHON3" - "$ZIP_PATH" "$EXTRACT_DIR" <<'PY'
import os, sys, zipfile, stat
archive, dest = sys.argv[1], sys.argv[2]
required = {
    "free_waf_threat_sync/free_waf_threat_sync.py",
    "free_waf_threat_sync/config.example.json",
    "free_waf_threat_sync/systemd/free-waf-threat-sync.service",
    "free_waf_threat_sync/systemd/free-waf-threat-sync.timer",
}
with zipfile.ZipFile(archive, "r") as zf:
    names = set()
    for info in zf.infolist():
        name = info.filename.replace("\\", "/")
        if name.startswith("/") or ".." in name.split("/"):
            raise SystemExit("压缩包包含不安全路径：" + name)
        if not name.startswith("free_waf_threat_sync/"):
            raise SystemExit("压缩包包含非预期顶层路径：" + name)
        mode = (info.external_attr >> 16) & 0o170000
        if mode == stat.S_IFLNK:
            raise SystemExit("压缩包包含符号链接，拒绝解压：" + name)
        names.add(name)
    missing = required - names
    if missing:
        raise SystemExit("安装包缺少必要文件：" + ", ".join(sorted(missing)))
    zf.extractall(dest)
print("安装包结构检查通过。")
PY

SOURCE_DIR="${EXTRACT_DIR}/free_waf_threat_sync"
NEW_APP="${SOURCE_DIR}/free_waf_threat_sync.py"
NEW_CONFIG="${SOURCE_DIR}/config.example.json"
NEW_SERVICE="${SOURCE_DIR}/systemd/free-waf-threat-sync.service"
NEW_TIMER="${SOURCE_DIR}/systemd/free-waf-threat-sync.timer"

mkdir -p "$APP_DIR" "$ETC_DIR" "$BACKUP_ROOT" /var/lib/free-waf-threat-sync /var/log/free-waf-threat-sync

backup_file "$APP" "free_waf_threat_sync.py" && OLD_APP=1 || true
backup_file "$CONFIG" "config.json" && OLD_CONFIG=1 || true
backup_file "$SERVICE" "free-waf-threat-sync.service" && OLD_SERVICE=1 || true
backup_file "$TIMER" "free-waf-threat-sync.timer" && OLD_TIMER=1 || true

if systemctl is-active --quiet "${UNIT_NAME}.service"; then
  die "同步服务当前正在运行。为避免更新中断，请等待本次任务结束后重新执行安装脚本。"
fi
if systemctl is-active --quiet "${UNIT_NAME}.timer"; then WAS_TIMER_ACTIVE=1; fi
if systemctl is-enabled --quiet "${UNIT_NAME}.timer"; then WAS_TIMER_ENABLED=1; fi

if [[ "$WAS_TIMER_ACTIVE" -eq 1 ]]; then
  log "检测到原自动定时器正在运行，先暂停定时触发以安全更新文件。"
  systemctl stop "${UNIT_NAME}.timer"
fi

MUTATION_STARTED=1
install -m 750 "$NEW_APP" "$APP"
install -m 644 "$NEW_SERVICE" "$SERVICE"
install -m 644 "$NEW_TIMER" "$TIMER"

if [[ ! -f "$CONFIG" ]]; then
  log "首次安装：创建配置文件，并采用保守情报源预设（IPsum Level 5 + Spamhaus；关闭 FireHOL Level 2）。"
  cp "$NEW_CONFIG" "$CONFIG"
  "$PYTHON3" - "$CONFIG" <<'PY'
import json, os, sys
p = sys.argv[1]
with open(p, "r") as f:
    c = json.load(f)
s = c.get("sources", {})
if "ipsum_level4" in s:
    s["ipsum_level4"]["url"] = "https://raw.githubusercontent.com/stamparm/ipsum/master/levels/5.txt"
    s["ipsum_level4"]["name"] = "IPsum Level 5（至少出现在5个名单）"
    s["ipsum_level4"]["enabled"] = True
    s["ipsum_level4"]["required"] = True
if "firehol_level2" in s:
    s["firehol_level2"]["enabled"] = False
    s["firehol_level2"]["required"] = False
if "spamhaus_drop" in s:
    s["spamhaus_drop"]["enabled"] = True
    s["spamhaus_drop"]["refresh_minutes"] = 1440
if "policy" in c:
    c["policy"]["source_priority"] = ["ipsum_level4", "spamhaus_drop"]
t = p + ".tmp"
with open(t, "w") as f:
    json.dump(c, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.chmod(t, 0o600)
os.rename(t, p)
PY
  chmod 600 "$CONFIG"
else
  log "检测到已有 config.json：保留所有现有配置，不覆盖你的情报源设置。"
fi

# Make the systemd unit use the Python interpreter found on this host.
sed -i "s|^ExecStart=/usr/bin/python3 |ExecStart=${PYTHON3} |" "$SERVICE"

if ! grep -Fq "${APP}" "$SERVICE" || ! grep -Fq -- "--apply" "$SERVICE"; then
  rollback_install
  die "systemd service 文件内容不符合预期，已恢复安装前文件。"
fi

systemctl daemon-reload

log "运行程序自检……"
if ! "$PYTHON3" "$APP" --self-test; then
  rollback_install
  die "程序自检失败，已恢复安装前文件。"
fi

log "执行一次模拟采集（不会修改 WAF，也不会 reload Nginx）……"
if ! "$PYTHON3" "$APP" --config "$CONFIG"; then
  rollback_install
  die "模拟采集失败。未启用自动任务；已恢复安装前程序和 systemd 文件。"
fi

ok "程序安装、自检及模拟采集全部通过。"
echo
log "安装备份目录：$BACKUP_DIR"
log "配置文件：$CONFIG"
log "程序文件：$APP"
log "自动任务：每30分钟检查；只有名单变化时才会正式写入并尝试平滑 reload。"
echo

if [[ "$NO_TIMER" -eq 1 ]]; then
  systemctl disable --now "${UNIT_NAME}.timer" >/dev/null 2>&1 || true
  warn "已按 --no-timer 要求完成安装，自动同步保持关闭。"
elif [[ "$WAS_TIMER_ACTIVE" -eq 1 || "$AUTO_YES" -eq 1 ]]; then
  systemctl enable --now "${UNIT_NAME}.timer"
  ok "systemd 自动同步已启用。"
elif [[ "$WAS_TIMER_ENABLED" -eq 1 ]]; then
  systemctl enable "${UNIT_NAME}.timer" >/dev/null
  warn "保留原先 enabled 状态；定时器当前未运行。执行 bash install.sh --start 可启动。"
else
  echo "自动任务会每30分钟执行一次正式同步（--apply），更新 free_waf 黑名单；只有名单变化时才会尝试 Nginx 平滑 reload。"
  echo "当前模拟已通过，但开启后将自动执行真实封禁规则。"
  if [[ -t 0 ]]; then
    read -r -p "现在启用自动同步吗？[y/N] " ANSWER
  else
    ANSWER="n"
    warn "非交互运行，默认不启用定时器。需要启用时运行：bash install.sh --start"
  fi
  case "$ANSWER" in
    y|Y|yes|YES)
      systemctl enable --now "${UNIT_NAME}.timer"
      ok "systemd 自动同步已启用。"
      ;;
    *)
      warn "已完成安装，但没有启用自动同步。运行 bash install.sh --start 可开启。"
      ;;
  esac
fi

echo
if systemctl is-active --quiet "${UNIT_NAME}.timer"; then
  ok "定时器状态：运行中"
  systemctl list-timers --all | grep -F "$UNIT_NAME" || true
else
  warn "定时器当前未运行。"
fi
cat <<'EOF'

常用命令：
  查看状态：bash install.sh --status
  启动自动同步：bash install.sh --start
  停止自动同步：bash install.sh --stop
  查看运行日志：journalctl -u free-waf-threat-sync.service -n 50 --no-pager
  手动模拟：python3 /opt/free-waf-threat-sync/free_waf_threat_sync.py --config /etc/free-waf-threat-sync/config.json
  手动同步：python3 /opt/free-waf-threat-sync/free_waf_threat_sync.py --config /etc/free-waf-threat-sync/config.json --apply

注意：白名单只读；现有 WAF 黑名单和配置文件会备份/保留。自动同步可能导致 Nginx 平滑 reload。
EOF
