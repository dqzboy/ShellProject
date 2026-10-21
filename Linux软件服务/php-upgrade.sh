#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2016,SC1091
# =============================================================================
#  php-upgrade.sh — 通过 Remi 仓库升级 / 打补丁 PHP
#
#  支持:  RHEL / CentOS Stream / Rocky / AlmaLinux 8 / 9 / 10   (dnf module 流)
#         CentOS 7                                         (yum 版本仓库)
#
#  两条通道，互不干扰：
#    版本升级  换 minor（8.4 -> 8.5），走 module stream 切换
#    安全补丁  只升 patch（8.5.11 -> 8.5.12），绝不动 minor，可重复执行
#
#  用法:
#    sudo ./php-upgrade.sh                  # 交互菜单（推荐，不用记参数）
#    sudo ./php-upgrade.sh --security      # 只打安全补丁（保持当前分支）
#    sudo ./php-upgrade.sh --apply         # 版本升级到 8.5
#    sudo ./php-upgrade.sh -v 8.4 --apply  # 版本升级到 8.4
#    sudo ./php-upgrade.sh --status        # 只看当前状态
#
#  参数:
#    -v, --php <ver>        目标版本，默认 8.5（7.4 / 8.0–8.5）
#        --apply            真正执行版本升级（不加则只预演）
#        --security         安全补丁通道：同分支内 patch 级升级
#        --min-version <v>  断言最低版本，如 8.5.12；不满足即失败（通用合规校验）
#        --status           只打印当前状态后退出
#        --mirror <源>      切换 remi 源：official | tuna | ustc
#    -y, --yes              无人值守：不再确认，失败自动回滚
#        --imagick          强制安装/升级 php-pecl-imagick（im7 优先）
#        --no-imagick       完全跳过 imagick
#        --menu             强制进入交互菜单
#    -h, --help             显示本帮助
# =============================================================================

set -uo pipefail

ARG_COUNT=$#
PROG=${0##*/}
SCRIPT_VER="build-20261021-2325"   # 用于确认手上跑的是不是最新一份
# build-20261021-2325 修复三处：
#   1) 换源 sed 只匹配 https://rpms.remirepo.net/，而官方文件里是 http://，
#      且 [remi-safe]/[remi-modular] 的路径是 safe/ modular/ 而非 remi/ -> 地址根本没换
#   2) grep -l 'a\|b' 用 BRE 交替，BSD grep 不支持；改用 ls 锁定 remi*.repo
#   3) 已在目标分支时仍提示"即将把 PHP 升级到 X"
TARGET=${PHP_TARGET_VERSION:-8.5}
MODE="plan"              # plan | apply | security | status
INTERACTIVE=0
ASSUME_YES=0
MIN_VERSION=""           # 通用合规基线，如 8.5.12
IMAGICK_MODE="auto"      # auto=仅在已装时升级 | always | never
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_ROOT="/var/backups"          # 所有备份统一放这里
BACKUP_DIR=""
REPO_READY=""
META_READY=""
PM=""
EL_MAJOR=""
PRETTY_OS=""
CUR_STREAM=""
CUR_VER=""
PREV_HIST=""
FPM_UNIT=""
declare -a PHP_PKGS=()
declare -a REPO_ARGS=()
declare -a PROBE_ARGS=()
declare -a LEFTOVER=()
declare -a LOST_EXT=()
VER_OPTS=(7.4 8.0 8.1 8.2 8.3 8.4 8.5)
PICKED=""
CAND_SUFFIX=""
CAND_VALUE=""
PROBE_ELAPSED=0
NET_CHECKED=""
NET_RC=0
MIRROR=""
MIRROR_KIND="remi"        # remi | epel | os —— 决定 --mirror 改哪一类源
SYS_EPEL_HOST=""
SYS_EPEL_ROOT=""
SYS_OS_HOST=""
SYS_OS_ROOT=""
SYS_OS_PREFIX=""
STREAM_CACHE=""
# 转圈动画帧（braille），run_probe 用；PROBE_LABEL 由调用方设置
SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
PROBE_LABEL=""
# 元数据刷新的总预算，可用环境变量覆盖：PHP_UPGRADE_PROBE_TIMEOUT=300
PROBE_LIMIT="${PHP_UPGRADE_PROBE_TIMEOUT:-180}"

if [ -t 1 ]; then
  C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_C=$'\033[36m'; C_D=$'\033[2m'; C_B=$'\033[1m'; C_N=$'\033[0m'
else
  C_R=; C_G=; C_Y=; C_C=; C_D=; C_B=; C_N=
fi

# 只读查询的公共选项：自动接受 GPG key（首次访问 remi-modular 会交互提示，
# 不加这个脚本就会卡住）、缩短超时、少重试；外层再套 timeout 兜底
RO_OPTS=(--setopt=assumeyes=True --setopt=timeout=30 --setopt=retries=1)
RO_TIMEOUT=120

log()  { printf '%s\n' "$*"; }
info() { log "${C_C}[INFO]${C_N} $*"; }
ok()   { log "${C_G}[ OK ]${C_N} $*"; }
warn() { log "${C_Y}[WARN]${C_N} $*"; }
bad()  { log "${C_R}[ !! ]${C_N} $*"; }
step() { log ""; log "${C_B}${C_C}==> $*${C_N}"; }
die()  { log "${C_R}[FAIL]${C_N} $*"; exit 1; }

usage() {
  awk 'NR < 4 { next } /^# ={3,}/ { exit } { print }' "$0" \
    | sed -e 's/^#[[:space:]]\{0,1\}//'
  printf '\n  版本: %s\n' "$SCRIPT_VER"
}

version_ok() {
  case "$1" in
    7.4|8.0|8.1|8.2|8.3|8.4|8.5) return 0 ;;
    *) return 1 ;;
  esac
}

# ver_ge A B  ->  A >= B
ver_ge() {
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]
}

minor_of() { printf '%s' "$1" | awk -F. '{ print $1"."$2 }'; }

# ---------------------------------------------------------------------------
# 参数
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--php)         [ $# -ge 2 ] || die "$1 需要参数"; TARGET="$2"; shift 2 ;;
    --apply)          MODE="apply"; shift ;;
    --security)       MODE="security"; shift ;;
    --min-version)    [ $# -ge 2 ] || die "$1 需要参数"; MIN_VERSION="$2"; shift 2 ;;
    --status)         MODE="status"; shift ;;
    --mirror)         [ $# -ge 2 ] || die "$1 需要参数"; MIRROR="$2"; MODE="mirror"; shift 2 ;;
    --menu)           INTERACTIVE=1; shift ;;
    -y|--yes)         ASSUME_YES=1; shift ;;
    --imagick)        IMAGICK_MODE="always"; shift ;;
    --no-imagick)     IMAGICK_MODE="never"; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                die "未知参数: $1（--help 查看用法）" ;;
  esac
done

[ "$ARG_COUNT" -eq 0 ] && INTERACTIVE=1
version_ok "$TARGET" || die "不支持的 PHP 版本 '$TARGET'（可选 7.4 / 8.0–8.5）"
SUFFIX=${TARGET//./}

# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------
collect_php_pkgs() {
  PHP_PKGS=()
  local n
  while IFS= read -r n; do
    [ -n "$n" ] && PHP_PKGS+=("$n")
  done < <(rpm -qa --qf '%{NAME}\n' 'php*' 2>/dev/null \
             | grep -E '^php$|^(php[0-9]{2}-)?php-' | sort -u)
}

history_last_id() {
  "$PM" history list --reverse 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { id = $1 } END { print id }'
}

# 只启用系统里真实存在的 remi 仓库，避免 "Unknown repo" 直接报错
build_repo_args() {
  REPO_ARGS=()
  PROBE_ARGS=()
  local avail r
  avail=$(timeout "$RO_TIMEOUT" "$PM" "${RO_OPTS[@]}" repolist --all 2>/dev/null \
            | awk 'NR > 1 && $1 ~ /^remi/ { print $1 }')
  local want=(remi remi-safe remi-modular "remi-php${SUFFIX}")
  for r in "${want[@]}"; do
    printf '%s\n' "$avail" | grep -qx "$r" && REPO_ARGS+=("--enablerepo=$r")
  done
  [ ${#REPO_ARGS[@]} -gt 0 ] || return 1
  # 探测类查询只加载 remi 仓库：php 包都在这里，
  # 关掉 baseos/appstream 能少下几十 MB 元数据，是"卡住"的主因
  PROBE_ARGS=(--disablerepo='*' "${REPO_ARGS[@]}")
  return 0
}

# 进程是否还"活着"。
# 注意：不能用 kill -0 —— 后台子进程退出后会变僵尸，kill -0 对僵尸仍然成功，
# 结果是明明 0.2 秒就完事的查询也要空等到超时上限（这就是"上限 180s 实际 190s"的元凶之一）。
proc_alive() {
  local p=$1 st
  if [ -d /proc/1 ]; then
    [ -d "/proc/$p" ] || return 1
    st=$(awk '/^State:/ { print $2 }' "/proc/$p/status" 2>/dev/null)
    [ "$st" = "Z" ] && return 1
    return 0
  fi
  st=$(ps -p "$p" -o state= 2>/dev/null | tr -d ' ')
  [ -z "$st" ] && return 1
  case "$st" in Z*) return 1 ;; esac
  return 0
}

# 后台跑查询 + 前台打心跳，结果走 stdout、进度走 stderr。
# 预算：limit 是"总共最多多少秒"。做法是让 timeout 提前 10s 发 TERM 给 dnf 收尾，
# 再用 -k 10 兜底强杀，两个加起来正好 = limit。
# 之前是 timeout limit 且没有 -k，dnf 收到 TERM 后还要收尾十几秒，
# 于是"上限 180s"实际跑到 190s —— 这里把承诺和现实对齐。
run_probe() {
  local limit=$1; shift
  local out pid rc=0 t=0 start elapsed soft grace
  start=$(date +%s)
  # soft + grace 必须正好等于 limit，否则小预算时总时长会翻倍
  if [ "$limit" -gt 20 ]; then
    grace=10; soft=$((limit - 10))
  else
    grace=1; soft=$((limit - 1))
  fi
  [ "$soft" -lt 1 ] && soft=1
  out=$(mktemp) || return 1
  ( timeout -k "$grace" "$soft" "$@" >"$out" 2>/dev/null ) &
  pid=$!

  # 转圈动画：0.2s 一帧，用 SECONDS 算已用时间（不 fork date）
  local t0=$SECONDS fr label="${PROBE_LABEL:-处理中}"
  while proc_alive "$pid"; do
    if [ -t 2 ]; then
      fr=${SPIN_FRAMES[$(( t % ${#SPIN_FRAMES[@]} ))]}
      printf '\r\033[K  %s%s%s %s … %ss / 上限 %ss' \
        "$C_C" "$fr" "$C_N" "$label" "$(( SECONDS - t0 ))" "$limit" >&2
    fi
    sleep 0.2
    t=$((t + 1))
    [ "$(( SECONDS - t0 ))" -ge "$limit" ] && break
  done
  [ -t 2 ] && printf '\r\033[K' >&2

  wait "$pid" 2>/dev/null || rc=$?
  elapsed=$(( $(date +%s) - start ))
  PROBE_ELAPSED=$elapsed
  cat "$out"
  rm -f "$out"
  return "$rc"
}

# 刷新 remi 仓库元数据。
# 注意：绝不能直接 `dnf makecache --refresh` —— 那会把 baseos / appstream / crb / epel
# 全部重拉一遍（几十 MB 以上），国内网络下能卡十几分钟。php 包只在 remi 里，
# 所以这里用 --disablerepo='*' 只刷 remi，其余仓库继续用本地缓存。
refresh_meta() {
  local rc
  info "刷新 remi 仓库元数据（只刷 remi，baseos/appstream 沿用缓存，上限 ${PROBE_LIMIT}s）"
  PROBE_LABEL="刷新 remi 元数据"
  run_probe "$PROBE_LIMIT" "$PM" "${RO_OPTS[@]}" -q "${PROBE_ARGS[@]}" makecache --refresh >/dev/null
  rc=$?
  PROBE_LABEL=""
  # 元数据变了，之前缓存的候选版本作废，必须重查
  CAND_SUFFIX=""
  CAND_VALUE=""
  if [ "$rc" -eq 0 ]; then
    ok "元数据已更新（用时 ${PROBE_ELAPSED}s）"
  elif [ "$PROBE_ELAPSED" -lt 5 ]; then
    # 秒失败 = 配置问题，不是网速问题。盲等 180s 也等不出来。
    bad "元数据刷新秒失败（${PROBE_ELAPSED}s），这是仓库配置错误，不是网络慢"
    warn "检查 remi 的 repo 文件里是否还有生效的 baseurl 或 mirrorlist："
    warn "  grep -E '^(baseurl|mirrorlist)' /etc/yum.repos.d/remi*.repo"
    warn "如果一条都没有（都被注释了），说明之前换源写坏了："
    warn "  sudo $PROG --mirror official    # 从 $BACKUP_ROOT/remi-repo-* 还原后重来"
  else
    warn "元数据刷新未完成（用时 ${PROBE_ELAPSED}s，上限 ${PROBE_LIMIT}s），继续用本地缓存"
    warn "链路太慢可加大预算: PHP_UPGRADE_PROBE_TIMEOUT=300 sudo -E $PROG ..."
  fi
  return 0
}

pkg_has_candidate() {
  local raw
  PROBE_LABEL="查询 $1"
  raw=$(run_probe 60 "$PM" -q "${RO_OPTS[@]}" "${PROBE_ARGS[@]}" list --available "$1")
  PROBE_LABEL=""
  printf '%s\n' "$raw" | grep -qF "$1."
}
# 仓库里 php-common 的最新版本（判断"目标分支有没有货 / 有没有新补丁"）
# 带缓存：菜单里反复预演不会每次都去问一遍仓库
candidate_php_common() {
  if [ -n "$CAND_SUFFIX" ] && [ "$CAND_SUFFIX" = "$SUFFIX" ]; then
    printf '%s' "$CAND_VALUE"
    return 0
  fi
  local raw v
  PROBE_LABEL="查询 php-common 候选版本"
  raw=$(run_probe 60 "$PM" -q "${RO_OPTS[@]}" "${PROBE_ARGS[@]}" list --available php-common)
  PROBE_LABEL=""
  v=$(printf '%s\n' "$raw" | awk '/^php-common\./ { print $2; exit }' | cut -d- -f1)
  if [ -n "$v" ]; then
    CAND_SUFFIX="$SUFFIX"
    CAND_VALUE="$v"
  fi
  printf '%s' "$v"
}

# 等一个回车再返回菜单。先排空输入缓冲区，
# 否则之前残留下来的换行会被菜单的 read 吃掉，表现为"连按好几个回车才有反应"。
drain_input() {
  local junk
  while IFS= read -rsn1 -t 0.05 junk 2>/dev/null; do :; done
}

detect_fpm_unit() {
  local u
  u=$(systemctl list-unit-files --type=service --no-legend 'php*fpm*' 2>/dev/null \
        | awk '{ print $1 }' | grep -E '\.service$' | head -1)
  if [ -n "$u" ]; then FPM_UNIT=${u%.service}
  elif systemctl list-unit-files --no-legend 'php-fpm.service' 2>/dev/null | grep -q php-fpm; then FPM_UNIT="php-fpm"
  else FPM_UNIT=""
  fi
}

current_php_version() {
  command -v php >/dev/null 2>&1 || return 0
  php -v 2>/dev/null | head -1 | awk '{ print $2 }'
}

# 所有 php 相关包的 name-version-release 快照，用来判断"这次到底有没有真的装上/升上东西"
php_pkg_snapshot() {
  rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 'php*' 2>/dev/null | sort
}

# ---------------------------------------------------------------------------
# 前置检查（轻量，不联网，供菜单快速显示）
# ---------------------------------------------------------------------------
preflight_light() {
  [ "$(id -u)" -eq 0 ] || die "请使用 root 或 sudo 运行"
  command -v rpm >/dev/null 2>&1 || die "这不是 RPM 系系统"
  command -v timeout >/dev/null 2>&1 || die "缺少 coreutils 的 timeout 命令"

  [ -r /etc/os-release ] || die "读不到 /etc/os-release"
  . /etc/os-release
  EL_MAJOR="${VERSION_ID%%.*}"
  PRETTY_OS="${PRETTY_NAME:-$ID $VERSION_ID}"
  [ -n "$EL_MAJOR" ] || die "无法识别发行版版本号"

  if command -v dnf >/dev/null 2>&1; then PM="dnf"
  elif command -v yum >/dev/null 2>&1; then PM="yum"
  else die "既没有 dnf 也没有 yum"
  fi

  step "环境"
  log "  发行版  : $PRETTY_OS  (el${EL_MAJOR})"
  log "  包管理器: $PM"
  log "  脚本版本: $SCRIPT_VER"
  case "$MODE" in
    security) log "  任务    : 安全补丁（保持当前分支）" ;;
    apply)    log "  任务    : 版本升级 -> PHP $TARGET" ;;
    status)   log "  任务    : 查看状态" ;;
    *)        log "  任务    : 版本升级预演 -> PHP $TARGET" ;;
  esac
  [ -n "$MIN_VERSION" ] && log "  合规基线: >= $MIN_VERSION"
}

# 需要仓库的部分，菜单选完再执行
ensure_repos() {
  rpm -q remi-release >/dev/null 2>&1 \
    || die "未安装 remi-release。先执行: $PM install -y https://rpms.remirepo.net/enterprise/remi-release-${EL_MAJOR}.rpm"

  # 安全补丁通道不换分支，按当前分支的仓库名构建
  if [ "$MODE" = security ]; then
    CUR_VER=$(current_php_version)
    [ -n "$CUR_VER" ] || die "未安装 PHP，安全补丁通道无从谈起；用 --apply 做版本安装/升级"
    TARGET=$(minor_of "$CUR_VER")
    version_ok "$TARGET" || die "当前 PHP $CUR_VER 属于不受支持的分支"
    SUFFIX=${TARGET//./}
  fi

  rpm -q epel-release >/dev/null 2>&1 \
    || warn "未安装 epel-release，php-pecl-mcrypt 等个别包可能找不到"

  if [ "$PM" = yum ] && [ "$EL_MAJOR" -lt 8 ]; then
    case "$TARGET" in
      8.4|8.5) die "EL${EL_MAJOR} 已 EOL，Remi 不再为 el7 构建 PHP $TARGET（el7 最高到 8.3 左右）" ;;
    esac
    warn "EL7 已 EOL，不建议继续承载生产 PHP"
  fi

  # 仓库集合只取决于分支，菜单里反复切换动作时不必重复构建
  if [ "$REPO_READY" != "$SUFFIX" ]; then
    info "读取 dnf 仓库配置 ..."
    build_repo_args || die "未找到任何 remi 仓库，请检查 remi-release 是否完整安装"
    info "启用仓库: ${REPO_ARGS[*]}"
    REPO_READY="$SUFFIX"
  fi

  # 先花几秒钟测源，别一上来就闷头下几十 MB 元数据
  check_connectivity

  # 只有真升级/打补丁才需要最新元数据（打补丁尤其要，否则看不到新包）
  if { [ "$MODE" = apply ] || [ "$MODE" = security ]; } && [ "$META_READY" != "$SUFFIX" ]; then
    if [ "$NET_RC" = 2 ]; then
      warn "所有源都不可达，跳过元数据刷新；先解决网络或换源再说"
    else
      refresh_meta
    fi
    META_READY="$SUFFIX"
  fi
}

# ---------------------------------------------------------------------------
# 源连通性自检（中国机房访问 rpms.remirepo.net 经常直接超时）
# ---------------------------------------------------------------------------
probe_url() {   # $1=名称 $2=url；可达则记录耗时到 PROBE_LAST_T 并返回 0
  local label=$1 url=$2 out code t size
  PROBE_LAST_T=""
  if out=$(curl -fsS -o /dev/null --connect-timeout 4 --max-time 8 \
             -w '%{http_code} %{time_total} %{size_download}' "$url" 2>/dev/null); then
    code=${out%% *}; out=${out#* }
    t=${out%% *}; size=${out##* }
    PROBE_LAST_T=$t
    log "  ${C_G}✓${C_N} ${label}   HTTP ${code}   ${t}s   ${size}B"
    return 0
  fi
  log "  ${C_R}✗${C_N} ${label}   不可达（超时/拒绝/证书问题）"
  return 1
}

check_connectivity() {
  [ "$NET_CHECKED" = "$EL_MAJOR" ] && return "$NET_RC"
  NET_CHECKED="$EL_MAJOR"
  NET_RC=0

  step "Remi 源连通性"
  if ! command -v curl >/dev/null 2>&1; then
    warn "没有 curl，跳过连通性检查"
    return 0
  fi
  info "正在探测 3 个源（每个最多 8s，全部不可达会提前结束）"

  local path="enterprise/${EL_MAJOR}/safe/x86_64/repodata/repomd.xml"
  local off_ok=0 cn_ok=0 off_t="" curm
  local lo="官方 remirepo" lt="清华 TUNA    " lu="中科大 USTC  "

  # 先告诉你现在用的是哪个，再谈别的
  curm=$(current_remi_mirror)
  info "当前使用: $(mirror_label "$curm")"
  [ "$curm" = official ] && lo="$lo  ${C_G}← 当前${C_N}"
  [ "$curm" = tuna ]     && lt="$lt  ${C_G}← 当前${C_N}"
  [ "$curm" = ustc ]     && lu="$lu  ${C_G}← 当前${C_N}"

  probe_url "$lo" "https://rpms.remirepo.net/${path}" && { off_ok=1; off_t=$PROBE_LAST_T; }
  probe_url "$lt" "https://mirrors.tuna.tsinghua.edu.cn/remi/${path}" && cn_ok=1
  probe_url "$lu" "https://mirrors.ustc.edu.cn/remi/${path}" && cn_ok=1

  # 已经在用国内镜像且探得到，就别再劝人换了
  if [ "$curm" = tuna ] || [ "$curm" = ustc ]; then
    if [ "$cn_ok" = 1 ]; then
      ok "当前已使用国内镜像，连通正常，无需切换"
      NET_RC=0
    else
      warn "当前配的是国内镜像但探测不通过，镜像可能正在同步或故障"
      log "  ${C_D}可先切回官方或换另一个国内镜像: sudo $PROG --mirror tuna|ustc|official${C_N}"
      NET_RC=2
    fi
    return 0
  fi

  if [ "$off_ok" = 1 ] && [ "$cn_ok" = 0 ]; then
    ok "官方源可用（${off_t}s），保持现状"
  elif [ "$cn_ok" = 1 ]; then
    if [ "$off_ok" = 1 ]; then
      warn "官方源可达（${off_t}s）但国内镜像更快，下载元数据慢的话可以换"
    else
      warn "官方源不可达 —— 这正是一直卡在'刷新元数据'的原因，建议换国内镜像"
    fi
    log "  ${C_D}一键切换: sudo $PROG --mirror tuna    （或 ustc）${C_N}"
    log "  ${C_D}换回官方: sudo $PROG --mirror official${C_N}"
    NET_RC=1
  else
    bad "三个源都不可达：检查 DNS、代理、出网策略或防火墙"
    log "  ${C_D}先手工确认: curl -I https://mirrors.ustc.edu.cn/remi/  或检查 /etc/resolv.conf${C_N}"
    NET_RC=2
  fi
  return 0
}

# 菜单里的"测源连通性"：测完直接给切换选项，不用再去记参数
nettest_action() {
  local mc
  NET_CHECKED=""
  check_connectivity

  if [ "$NET_RC" = 1 ] && [ -t 0 ]; then
    local curm
    curm=$(current_remi_mirror)
    log ""
    log "  ${C_B}直接切换？${C_N}   ${C_D}（当前: $(mirror_label "$curm")）${C_N}"
    if [ "$curm" = tuna ]; then
      log "    1) 清华 TUNA     ${C_G}← 当前${C_N}"
    else
      log "    1) 清华 TUNA"
    fi
    if [ "$curm" = ustc ]; then
      log "    2) 中科大 USTC   ${C_G}← 当前${C_N}"
    else
      log "    2) 中科大 USTC"
    fi
    log "    3) 先不切"
    printf "请选择 [1-3]: "
    read -r mc || return 0
    case "$mc" in
      1) apply_mirror tuna ;;
      2) apply_mirror ustc ;;
      *) info "保持现状；想换时执行: $PROG --mirror tuna" ;;
    esac
  elif [ "$NET_RC" = 2 ]; then
    warn "三个源都不通，换镜像也没用，先排查网络："
    log "  ${C_D}1. DNS:     cat /etc/resolv.conf ; getent hosts mirrors.ustc.edu.cn${C_N}"
    log "  ${C_D}2. 出网:    curl -I https://mirrors.ustc.edu.cn/remi/  --max-time 5${C_N}"
    log "  ${C_D}3. 代理:    env | grep -i proxy${C_N}"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 切换 Remi 镜像（改 /etc/yum.repos.d/remi*.repo，先备份）
# ---------------------------------------------------------------------------
apply_mirror() {
  local which=$1 base="" desc=""
  case "$which" in
    official) base="https://rpms.remirepo.net";            desc="官方 remirepo" ;;
    tuna)     base="https://mirrors.tuna.tsinghua.edu.cn/remi"; desc="清华 TUNA" ;;
    ustc)     base="https://mirrors.ustc.edu.cn/remi";     desc="中科大 USTC" ;;
    *) die "未知镜像: $which（official | tuna | ustc）" ;;
  esac

  step "切换 Remi 源 -> $desc"

  # 官方源就是在 remi-release 里写的，直接还原备份最干净
  if [ "$which" = official ]; then
    local latest
    # 新路径优先；兼容早期版本写在 /root 下的备份
    latest=$(ls -1dt "$BACKUP_ROOT"/remi-repo-* /root/remi-repo-backup-* 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
      cp -a "$latest"/remi*.repo /etc/yum.repos.d/ 2>/dev/null \
        && ok "已用 $latest 里的原始配置还原" || die "还原失败，请手工检查 $latest"
    else
      warn "没有历史备份，重新安装 remi-release 恢复默认源"
      "$PM" -y reinstall remi-release >/dev/null 2>&1 || die "reinstall remi-release 失败"
      ok "已重装 remi-release"
    fi
  else
    local path="enterprise/${EL_MAJOR}/safe/x86_64/repodata/repomd.xml"
    probe_url "$desc" "${base}/${path}" || die "$desc 也不可达，先解决网络再切换"

    # 按文件名锁定，不要用 grep -l 'remirepo.net|tuna|ustc'：
    #   · BRE 的 \| 在 BSD/macOS grep 上不支持（会一个文件都匹配不到）
    #   · 万一当前用的是第三方自定义镜像，按域名筛会把所有文件都漏掉
    local files f
    files=$(ls -1 /etc/yum.repos.d/remi*.repo 2>/dev/null)
    [ -n "$files" ] || die "没找到 remi 的 repo 文件（/etc/yum.repos.d/remi*.repo）"

    BACKUP_DIR="$BACKUP_ROOT/remi-repo-$TS"
    mkdir -p "$BACKUP_DIR"
    cp -a /etc/yum.repos.d/remi*.repo "$BACKUP_DIR"/ 2>/dev/null || true
    ok "原配置已备份到 $BACKUP_DIR"

    for f in $files; do
      # ── 关键：只换 scheme+host（顺带吃掉可选的 /remi），路径原样保留 ──
      # 不能写死整串 URL，两个坑都真实踩过：
      #   1) remi-release 官方文件里是 http:// ，不是 https://
      #   2) 官方路径没有 /remi 这一段（enterprise/9/safe/...），
      #      镜像站才有（/remi/enterprise/9/safe/...）
      # 所以按"结构"匹配：baseurl= + 协议 + 主机 + 可选 /remi，后面路径一律不动。
      sed -i -E \
        -e 's|^([[:space:]]*)#([[:space:]]*baseurl[[:space:]]*=)|\1\2|' \
        -e "s|^([[:space:]]*baseurl[[:space:]]*=)[[:space:]]*[a-zA-Z]+://[^/[:space:]]+(/remi)?/|\1${base}/|" \
        "$f"

      # 先验证 baseurl 真换成目标镜像了，再去动 mirrorlist。
      # 顺序反了就会留下"mirrorlist 注释掉、baseurl 又没换上"的空仓库。
      if ! grep -qE "^[[:space:]]*baseurl[[:space:]]*=[[:space:]]*${base}/" "$f"; then
        cp -a "$BACKUP_DIR/$(basename "$f")" "$f"
        bad "$(basename "$f") 的 baseurl 没换成 $base ，已从备份还原，仓库配置未改动"
        warn "它原本长这样（把这段发我，我按你的实际格式调）："
        grep -E '^[[:space:]]*#?[[:space:]]*baseurl[[:space:]]*=' "$BACKUP_DIR/$(basename "$f")" | sed 's/^/      /'
        die "这是地址格式没匹配上，不是网络问题"
      fi

      # baseurl 已生效，才把 mirrorlist 注释掉（避免两条源并存互相打架）
      sed -i -E 's|^[[:space:]]*mirrorlist[[:space:]]*=|#mirrorlist=|' "$f"

      # 兜底：必须还有生效的源
      if ! grep -qE '^[[:space:]]*(baseurl|mirrorlist)[[:space:]]*=' "$f"; then
        cp -a "$BACKUP_DIR/$(basename "$f")" "$f"
        bad "$(basename "$f") 改写后没有可用源，已从备份还原"
        die "仓库配置未改动"
      fi

      ok "已更新 $(basename "$f")"
      grep -E '^[[:space:]]*baseurl[[:space:]]*=' "$f" | sed 's|^[[:space:]]*|      |'
    done
  fi

  # 换了源必须清缓存，否则 dnf 还拿着旧 baseurl 的元数据。
  # 但只清 remi：`dnf clean all` 会把 baseos/appstream/epel 一起清掉，
  # 接着 makecache 就得重下几十 MB —— 这就是"清理缓存并重新拉元数据"很慢的原因。
  REPO_READY=""; META_READY=""; CAND_SUFFIX=""; CAND_VALUE=""; NET_CHECKED=""
  build_repo_args 2>/dev/null || true

  if [ ${#PROBE_ARGS[@]} -gt 0 ]; then
    PROBE_LABEL="清理 remi 旧缓存"
    run_probe 60 "$PM" "${RO_OPTS[@]}" -q "${PROBE_ARGS[@]}" clean metadata >/dev/null
    PROBE_LABEL="重新拉取 remi 元数据"
    run_probe "$PROBE_LIMIT" "$PM" "${RO_OPTS[@]}" -q "${PROBE_ARGS[@]}" makecache >/dev/null \
      && ok "元数据就绪（用时 ${PROBE_ELAPSED}s）" \
      || warn "makecache 未完成，可稍后手动: $PM makecache"
  else
    warn "没识别出 remi 仓库，只能全量刷新（会比较慢）"
    PROBE_LABEL="全量刷新元数据"
    run_probe "$PROBE_LIMIT" "$PM" -q makecache >/dev/null \
      && ok "元数据就绪" || warn "makecache 未完成"
  fi
  PROBE_LABEL=""
  return 0
}

# ---------------------------------------------------------------------------
# 交互菜单
# ---------------------------------------------------------------------------
# 方向键选版本：↑/↓ 移动，空格或回车确认，q 取消。结果放 PICKED
pick_version() {
  local -a opts=("${VER_OPTS[@]}")
  local n=${#opts[@]} i idx=0 key seq

  for i in "${!opts[@]}"; do
    [ "${opts[$i]}" = "$TARGET" ] && idx=$i
  done

  _ver_draw() {
    local j
    for j in "${!opts[@]}"; do
      if [ "$j" -eq "$1" ]; then
        printf '\r\033[K   %s❯ %s%s\n' "$C_G" "${opts[$j]}" "$C_N"
      else
        printf '\r\033[K     %s\n' "${opts[$j]}"
      fi
    done
  }

  log "  ${C_D}↑/↓ 选择，空格或回车确认，q 取消${C_N}"
  _ver_draw "$idx"

  while :; do
    IFS= read -rsn1 key || return 1
    case "$key" in
      $'\x1b')
        # 用小整数超时读后续两字节：老 bash（如 3.2）不支持 0.05 这种小数
        IFS= read -rsn2 -t 1 seq
        case "$seq" in
          '[A') idx=$(( (idx - 1 + n) % n )) ;;
          '[B') idx=$(( (idx + 1) % n )) ;;
          '')   printf '\033[%dA\033[K' "$n"; return 1 ;;   # 单按 Esc 取消
          *)    continue ;;
        esac
        ;;
      ' '|'') break ;;                                    # 空格 / 回车
      q|Q) printf '\033[%dA\033[K' "$n"; return 1 ;;
      *) continue ;;
    esac
    printf '\033[%dA' "$n"
    _ver_draw "$idx"
  done

  PICKED="${opts[$idx]}"
  printf '\r\033[K   %s✔ 已选 %s%s\n' "$C_G" "$PICKED" "$C_N"
  return 0
}

# 读当前启用的 php stream。
# 关键：不要一上来就 `dnf module list` —— 它要加载仓库元数据，官方源不通时会静默卡 20 秒，
# 表现就是"打完环境检测就卡住"。dnf 自己把已启用的 stream 记在
# /etc/dnf/modules.d/php.module 里，读文件是纯本地操作，0 延迟。
enabled_php_stream() {
  local f=/etc/dnf/modules.d/php.module st
  if [ -n "${STREAM_CACHE:-}" ]; then printf '%s' "$STREAM_CACHE"; return 0; fi
  if [ -r "$f" ]; then
    st=$(awk -F= '/^[[:space:]]*stream[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$f")
    if [ -n "$st" ]; then
      STREAM_CACHE=$st
      printf '%s' "$st"
      return 0
    fi
  fi
  # 兜底才问 dnf，超时压到 8s
  if [ "$PM" = dnf ]; then
    st=$(timeout 8 "$PM" "${RO_OPTS[@]}" module list --enabled php 2>/dev/null \
           | awk '$1 == "php" && $3 == "[e]" { print $2; exit }')
    [ -n "$st" ] && STREAM_CACHE=$st
    printf '%s' "$st"
  fi
}

# ===========================================================================
#  系统源（CentOS / EPEL）——影响 PHP 升级的实际瓶颈就在这里
#
#  实测一台腾讯云服务器（2026-10-21）的 dnf distro-sync 'php*'：
#    CentOS Stream 9 - AppStream    95 MB/s   ✓
#    CentOS Stream 9 - BaseOS       41 MB/s   ✓
#    CentOS Stream 9 - CRB          2.1 MB/s  ✓
#    Aeris（repo.aerisnetwork.com）  6.0 kB/s  ✗  纯浪费
#    Extra Packages for EL 9 (EPEL)  11 kB/s   ✗  ETA 30 分 33 秒 ← 就是它
#  结论：官方源不是瓶颈，EPEL 的 metalink 才是。所以要切的是 EPEL。
# ===========================================================================

# EPEL 的镜像地址。EPEL 的 repo 文件用的是 metalink=，不是 baseurl=，
# 切换时必须同时注释 metalink 并写入 baseurl——这是和 remi 最大的不同。
SYS_EPEL_HOST=""
SYS_EPEL_ROOT=""

sys_epel_candidates() {
  case "$1" in
    tuna)  SYS_EPEL_HOST="mirrors.tuna.tsinghua.edu.cn"; SYS_EPEL_ROOT="/epel" ;;
    ustc)  SYS_EPEL_HOST="mirrors.ustc.edu.cn";       SYS_EPEL_ROOT="/epel" ;;
    aliyun) SYS_EPEL_HOST="mirrors.aliyun.com";       SYS_EPEL_ROOT="/epel" ;;
    huawei) SYS_EPEL_HOST="mirrors.huaweicloud.com";  SYS_EPEL_ROOT="/epel" ;;
    *) return 1 ;;
  esac
  return 0
}

sys_epel_label() {
  case "$1" in
    tuna)   printf '清华 TUNA（mirrors.tuna.tsinghua.edu.cn/epel）' ;;
    ustc)   printf '中科大 USTC（mirrors.ustc.edu.cn/epel）' ;;
    aliyun) printf '阿里云（mirrors.aliyun.com/epel，实测最快）' ;;
    huawei) printf '华为云（mirrors.huaweicloud.com/epel）' ;;
    official) printf '官方 metalink（mirrors.fedoraproject.org，国内很慢）' ;;
    custom:*) printf '自定义（%s）' "${1#custom:}" ;;
    unknown)  printf '未识别（没装 EPEL？）' ;;
  esac
}

# CentOS Stream 官方源的镜像。$contentdir/$stream 实际就是 centos-stream/9-stream。
sys_os_candidates() {
  case "$1" in
    tuna)   SYS_OS_HOST="mirrors.tuna.tsinghua.edu.cn";  SYS_OS_ROOT="" ;;
    ustc)   SYS_OS_HOST="mirrors.ustc.edu.cn";           SYS_OS_ROOT="" ;;
    aliyun) SYS_OS_HOST="mirrors.aliyun.com";           SYS_OS_ROOT="" ;;
    huawei) SYS_OS_HOST="mirrors.huaweicloud.com";      SYS_OS_ROOT="" ;;
    tencent) SYS_OS_HOST="mirrors.tencentyun.com";       SYS_OS_ROOT="" ;;
    *) return 1 ;;
  esac
  SYS_OS_PREFIX="/centos-stream/${EL_MAJOR}-stream"
  return 0
}

sys_os_label() {
  case "$1" in
    tuna)   printf '清华 TUNA（mirrors.tuna.tsinghua.edu.cn）' ;;
    ustc)   printf '中科大 USTC（mirrors.ustc.edu.cn）' ;;
    aliyun) printf '阿里云（mirrors.aliyun.com）' ;;
    huawei) printf '华为云（mirrors.huaweicloud.com）' ;;
    tencent) printf '腾讯云（mirrors.tencentyun.com，你当前在用）' ;;
    official) printf '官方 mirrorlist（mirrorlist.centos.org）' ;;
    custom:*) printf '自定义（%s）' "${1#custom:}" ;;
    unknown)  printf '未识别' ;;
  esac
}

# ── 通用：从 repo 文件里提取当前使用的镜像主机（不联网）────────────────
# $1 = 通配的 repo 文件列表（已展开）
detect_host() {
  local files="$1" h
  h=$(grep -hE '^[[:space:]]*(baseurl|mirrorlist|metalink)[[:space:]]*=' $files 2>/dev/null \
        | grep -viE 'download\.example|localhost' \
        | sed -E 's#^[^=]*=[[:space:]]*https?://([^/]+).*#\1#' \
        | grep -v '^$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  [ -n "$h" ] || { printf 'unknown'; return 0; }
  case "$h" in
    mirrors.fedoraproject.org)   printf 'official' ;;
    mirrorlist.centos.org)       printf 'official' ;;
    mirrors.tuna.tsinghua.edu.cn) printf 'tuna' ;;
    mirrors.ustc.edu.cn)         printf 'ustc' ;;
    mirrors.aliyun.com)          printf 'aliyun' ;;
    mirrors.huaweicloud.com)     printf 'huawei' ;;
    mirrors.tencentyun.com)      printf 'tencent' ;;
    *)                           printf 'custom:%s' "$h" ;;
  esac
}

current_epel_mirror() {
  detect_host "$(ls -1 /etc/yum.repos.d/epel*.repo 2>/dev/null)"
}

current_os_mirror() {
  detect_host "$(ls -1 /etc/yum.repos.d/CentOS-Stream*.repo /etc/yum.repos.d/centos.repo 2>/dev/null)"
}

# EPEL 仓库文件：只处理真正的 epel 主仓，不要碰 epel-next / epel-cisco-openh264
# （那两个的目录结构不同，next 是 /epel/next/9/...，混在一起会写错）
epel_repo_files() {
  ls -1 /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel-*.repo 2>/dev/null \
    | grep -vE 'epel-next|epel-cisco-openh264' \
    | while IFS= read -r f; do
        # 只要含 [epel] 段的（不含 -debuginfo/-source 单独文件的情况已由上面过滤）
        grep -qE '^\[epel\]' "$f" && printf '%s\n' "$f"
      done
}

# ── EPEL 切换 ──────────────────────────────────────────────────────────
# EPEL repo 文件的真实结构（官方发行版）：
#   [epel]
#   #baseurl=https://download.example/pub/epel/9/Everything/$basearch/   ← 注释里的示例地址，不能用
#   metalink=https://mirrors.fedoraproject.org/metalink?repo=epel-9&...
# 所以做法和 remi 完全不同：注释掉 metalink，然后在 section 里插入一条真的 baseurl。
apply_epel_mirror() {
  local which=$1 base desc path files f
  sys_epel_candidates "$which" || die "未知 EPEL 镜像: $which（tuna | ustc | aliyun | huawei | official）"
  base="https://${SYS_EPEL_HOST}${SYS_EPEL_ROOT}"
  desc=$(sys_epel_label "$which")

  step "切换 EPEL 源 -> $desc"

  files=$(epel_repo_files)
  [ -n "$files" ] || die "没找到 EPEL 的 repo 文件（/etc/yum.repos.d/epel.repo）"

  # 探测要用的那条路径（Everything 是主仓，体积最大也最常被卡）
  path="${EL_MAJOR}/Everything/x86_64/repodata/repomd.xml"
  probe_url "$desc" "${base}/${path}" \
    || die "$desc 不可达，先解决网络再切换（EPEL metalink 慢通常就是被它拖累的）"

  BACKUP_DIR="$BACKUP_ROOT/epel-repo-$TS"
  mkdir -p "$BACKUP_DIR"
  cp -a /etc/yum.repos.d/epel*.repo "$BACKUP_DIR"/ 2>/dev/null || true
  ok "原配置已备份到 $BACKUP_DIR"

  for f in $files; do
    local changed=0
    # 1) 注释 metalink（EPEL 用它做镜像发现，国内会被 metalink 里的境外节点拖死）
    if grep -qE '^[[:space:]]*metalink[[:space:]]*=' "$f"; then
      sed -i -E 's|^[[:space:]]*metalink[[:space:]]*=|#metalink=|' "$f"
      changed=1
    fi

    # 2) 每个 section 写入对应的 baseurl。
    #    这里不能用一行 sed 搞定：路径随 section 变化
    #    （epel -> 9/Everything、epel-debuginfo -> 9/Everything/debug、
    #      epel-source -> 9/Everything/source/tree），必须逐段处理。
    local sec="" sub="" newline="" had=0
    local tmp="$f.phpup.$$"
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
      # 原样写入注释行
      case "$line" in
        \#*baseurl=*|\#*metalink=*)
          printf '%s\n' "$line" >> "$tmp"
          continue
          ;;
      esac
      case "$line" in
        \[*)
          sec=$(printf '%s' "$line" | tr -d '[:space:]')
          case "$sec" in
            \[epel\])                       sub="9/Everything" ;;
            \[epel-debuginfo\])             sub="9/Everything/debug" ;;
            \[epel-source\])                sub="9/Everything/source/tree" ;;
            *)                             sub="" ;;
          esac
          had=0
          ;;
      esac
      # 旧的生效 baseurl 换成新地址
      if printf '%s' "$line" | grep -qE '^[[:space:]]*baseurl[[:space:]]*='; then
        if [ -n "$sub" ]; then
          newline="baseurl=${base}/${sub}/\$basearch/"
        else
          newline="#baseurl=${base}/${sub}/\$basearch/"
        fi
        printf '%s\n' "$newline" >> "$tmp"
        had=1
        changed=1
        continue
      fi
      printf '%s\n' "$line" >> "$tmp"
      # section 第一条非注释、非 name/gpgcheck 的配置行之后，若还没有 baseurl 就补一条
      if [ -n "$sub" ] && [ "$had" = 0 ]; then
        case "$line" in
          name=*|gpgcheck=*|gpgkey=*|repo_gpgcheck=*|countme=*|skip_if_unavailable=*|\[*) ;;
          ""|\#*) ;;
          *)
            printf 'baseurl=%s/%s/$basearch/\n' "$base" "$sub" >> "$tmp"
            had=1
            changed=1
            ;;
        esac
      fi
    done < "$f"
    mv "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; die "写入 $f 失败"; }

    if [ "$changed" = 0 ]; then
      bad "$(basename "$f") 没有可改的 baseurl/metalalink，未改动"
      continue
    fi

    # 安全网：必须有生效的 baseurl，且 metalink 已注释
    if ! grep -qE "^[[:space:]]*baseurl[[:space:]]*=[[:space:]]*${base}/" "$f"; then
      cp -a "$BACKUP_DIR/$(basename "$f")" "$f"
      bad "$(basename "$f") 没能写入 ${base}/... ，已从备份还原"
      warn "它原本长这样（发我我按实际格式调）："
      grep -nE '^[[:space:]]*(baseurl|metalink|#baseurl)[[:space:]]*=' "$BACKUP_DIR/$(basename "$f")" | sed 's/^/      /'
      die "EPEL 仓库配置未改动"
    fi

    ok "已更新 $(basename "$f")"
    grep -E '^[[:space:]]*baseurl[[:space:]]*=' "$f" | sed 's|^[[:space:]]*|      |'
  done

  refresh_sys_meta
  return 0
}

# 恢复 EPEL 官方配置
restore_epel_official() {
  step "恢复 EPEL 官方源（metalink）"
  local latest
  latest=$(ls -1dt "$BACKUP_ROOT"/epel-repo-* 2>/dev/null | head -1)
  if [ -n "$latest" ]; then
    cp -a "$latest"/epel*.repo /etc/yum.repos.d/ 2>/dev/null \
      && ok "已从 $latest 还原" || die "还原失败，请手工检查 $latest"
  else
    warn "没有历史备份，重新安装 EPEL 仓库定义恢复默认 metalink"
    "$PM" -y reinstall epel-release >/dev/null 2>&1 || die "reinstall epel-release 失败"
    ok "已重装 epel-release"
  fi
  refresh_sys_meta
}

# ── CentOS 官方源切换 ─────────────────────────────────────────────────
apply_os_mirror() {
  local which=$1 base desc files f
  sys_os_candidates "$which" || die "未知官方源镜像: $which（tuna | ustc | aliyun | huawei | tencent | official）"
  base="https://${SYS_OS_HOST}${SYS_OS_PREFIX}"
  desc=$(sys_os_label "$which")

  step "切换 CentOS 官方源 -> $desc"

  if [ "$which" = official ]; then
    local latest
    latest=$(ls -1dt "$BACKUP_ROOT"/os-repo-* 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
      cp -a "$latest"/*.repo /etc/yum.repos.d/ 2>/dev/null \
        && ok "已从 $latest 还原官方配置" || die "还原失败，请手工检查 $latest"
    else
      warn "没有历史备份，官方源一般由 dnf 发行版包提供，建议 yum reinstall centos-release 或手工检查"
    fi
    refresh_sys_meta
    return 0
  fi

  # 只处理 enabled=1 且真正在用的：baseos / appstream / crb
  # （Sources/Debuginfo/PowerTools 默认 enabled=0，改了也没意义，还会写坏 $basearch 变量）
  files=$(grep -lE '^[[:space:]]*baseurl[[:space:]]*=.*(centos-stream|\$contentdir)' \
            /etc/yum.repos.d/*.repo 2>/dev/null)
  [ -n "$files" ] || die "没找到用 baseurl 的 CentOS 官方 repo 文件"

  probe_url "$desc" "${base}/BaseOS/x86_64/os/repodata/repomd.xml" \
    || die "$desc 不可达，先解决网络再切换"

  BACKUP_DIR="$BACKUP_ROOT/os-repo-$TS"
  mkdir -p "$BACKUP_DIR"
  cp -a /etc/yum.repos.d/*.repo "$BACKUP_DIR"/ 2>/dev/null || true
  ok "原配置已备份到 $BACKUP_DIR"

  for f in $files; do
    # 官方源和 remi 一样：只换 scheme+host，路径原样保留（$contentdir/$stream 也在路径里）
    sed -i -E \
      -e 's|^([[:space:]]*)#([[:space:]]*baseurl[[:space:]]*=)|\1\2|' \
      -e 's|^([[:space:]]*)#([[:space:]]*mirrorlist[[:space:]]*=)|\1\2|' \
      -e "s|^([[:space:]]*(baseurl|mirrorlist)[[:space:]]*=)[[:space:]]*https?://[^/[:space:]]+(/centos-stream)?/|\1${base}/|" \
      -e 's|^([[:space:]]*mirrorlist[[:space:]]*=)|\1#|' \
      "$f"

    if ! grep -qE "^[[:space:]]*baseurl[[:space:]]*=[[:space:]]*${base}/" "$f"; then
      cp -a "$BACKUP_DIR/$(basename "$f")" "$f"
      bad "$(basename "$f") 的 baseurl 没换成 $base ，已从备份还原，仓库配置未改动"
      warn "它原本长这样（发我我按实际格式调）："
      grep -E '^[[:space:]]*#?[[:space:]]*baseurl[[:space:]]*=' "$BACKUP_DIR/$(basename "$f")" | sed 's/^/      /'
      die "这是地址格式没匹配上，不是网络问题"
    fi

    ok "已更新 $(basename "$f")"
    grep -E '^[[:space:]]*baseurl[[:space:]]*=' "$f" | sed 's|^[[:space:]]*|      |'
  done

  refresh_sys_meta
  return 0
}

# 换完系统源后刷新缓存。只清这些源，不要 clean all
refresh_sys_meta() {
  REPO_READY=""; META_READY=""; CAND_SUFFIX=""; CAND_VALUE=""
  if [ ${#RO_OPTS[@]} -gt 0 ]; then
    PROBE_LABEL="刷新系统源元数据"
    run_probe 120 "$PM" "${RO_OPTS[@]}" -q clean metadata >/dev/null
    PROBE_LABEL="重新拉取系统源元数据"
    run_probe "$PROBE_LIMIT" "$PM" "${RO_OPTS[@]}" -q makecache >/dev/null \
      && ok "元数据就绪（用时 ${PROBE_ELAPSED}s）" \
      || warn "makecache 未完成，可稍后手动: $PM makecache"
  fi
  PROBE_LABEL=""
  return 0
}

# ── 重复 repo 检测 ─────────────────────────────────────────────────────
# 实测踩过的坑：CentOS-Stream-*.repo 和 centos.repo 同时定义 [baseos]，
# dnf 会刷一屏 "Repository baseos is listed more than once"。
# 这不影响功能但污染输出，也让排查变难，必须报出来。
find_duplicate_repos() {
  local out
  out=$(awk '
    FNR==1 { file=FILENAME }
    /^[[:space:]]*\[/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print FILENAME "\t" $0
    }
  ' /etc/yum.repos.d/*.repo 2>/dev/null \
    | sort -t"$(printf '\t')" -k2,2 \
    | awk -F'\t' '
      $2==prev { if (!inprint) { printf "  %-22s <- %s\n", $2, prevf; inprint=1 }
                  printf "  %-22s <- %s\n", "", $1 }
      $2!=prev { prev=$2; prevf=$1; inprint=0 }
    ')
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
  return 0
}

# ===========================================================================
#  系统源体检：哪些源在拖后腿（这是"为啥这么慢"的直接答案）
# ===========================================================================
audit_sys_repos() {
  step "系统源体检（PHP 升级会加载这些源的元数据）"

  local -a f
  if ! command -v curl >/dev/null 2>&1; then
    warn "没有 curl，跳过测速"
    return 0
  fi

  # 列出所有 enabled 的仓库，逐个测速。超时设 6s，慢源会明显暴露。
  local ids
  ids=$(timeout 30 "$PM" "${RO_OPTS[@]}" repolist --enabled 2>/dev/null | awk 'NR>1 {print $1}')
  if [ -z "$ids" ]; then
    warn "拿不到仓库列表（repolist 超时）"
    return 0
  fi

  info "逐个探测 repomd.xml 响应时间（超过 1s 就会明显拖慢 dnf）"
  log ""
  local slow="" id url n
  for id in $ids; do
    url=$(awk -v want="$id" '
      $0 ~ "^\\[" want "\\]$" { inb=1; next }
      /^\[/ { inb=0 }
      inb && /^[[:space:]]*baseurl[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
    ' /etc/yum.repos.d/*.repo 2>/dev/null | head -1)
    [ -n "$url" ] || continue
    url="${url%/}/repodata/repomd.xml"
    # 把 dnf 变量展开
    url=$(printf '%s' "$url" | sed -e "s/\$basearch/$(rpm -E '%{_arch}' 2>/dev/null || echo x86_64)/g" \
                             -e "s/\$releasever/${EL_MAJOR}/g" -e "s/\$stream/${EL_MAJOR}-stream/g" \
                             -e "s|\$contentdir|centos-stream/${EL_MAJOR}-stream|g")
    case "$url" in http://*|https://*) ;; *) continue ;; esac

    if probe_url "$id" "$url" >/dev/null 2>&1; then
      : # PROBE_LAST_T 已被 probe_url 填好
      if [ -n "$PROBE_LAST_T" ] && awk "BEGIN{exit !($PROBE_LAST_T > 1.0)}" 2>/dev/null; then
        log "  ${C_Y}⚠${C_N} $id   ${PROBE_LAST_T}s  ${C_D}偏慢${C_N}"
        slow="$slow $id"
      fi
    fi
  done

  log ""
  if [ -n "$slow" ]; then
    warn "这些源响应 >1s，dnf 会在这里耗掉大部分时间：$slow"
    log "  ${C_D}EPEL 用了 metalink= 指向 mirrors.fedoraproject.org，国内通常最慢${C_N}"
    log "  ${C_D}菜单 6 可切换 EPEL / 官方源${C_N}"
  else
    ok "所有仓库响应都< 1s，元数据加载不会成为瓶颈"
  fi

  # 重复定义
  local dups
  if dups=$(find_duplicate_repos); then
    log ""
    warn "以下 repo id 被多个文件重复定义（dnf 会刷 'listed more than once'）:"
    printf '%s\n' "$dups"
    log "  ${C_D}CentOS-Stream-*.repo 和 centos.repo 同时存在是常见原因；${C_N}"
    log "  ${C_D}删掉旧的那份即可：mv CentOS-Stream-BaseOS.repo{,.bak}${C_N}"
  fi
  return 0
}

# 当前 remi 用的是哪个源（读 repo 文件里生效的 baseurl/mirrorlist，不联网）
current_remi_mirror() {
  local h
  h=$(grep -hE '^[[:space:]]*(baseurl|mirrorlist)[[:space:]]*=' /etc/yum.repos.d/remi*.repo 2>/dev/null \
        | sed -E 's#^[^=]*=[[:space:]]*https?://([^/]+).*#\1#' \
        | grep -v '^$' | sort -u | head -1)
  [ -n "$h" ] || { printf 'unknown'; return 0; }
  case "$h" in
    mirrors.tuna.tsinghua.edu.cn) printf 'tuna' ;;
    mirrors.ustc.edu.cn)          printf 'ustc' ;;
    rpms.remirepo.net)            printf 'official' ;;
    *)                            printf 'custom:%s' "$h" ;;
  esac
}

mirror_label() {
  case "$1" in
    tuna)     printf '清华 TUNA（mirrors.tuna.tsinghua.edu.cn）' ;;
    ustc)     printf '中科大 USTC（mirrors.ustc.edu.cn）' ;;
    official) printf '官方（rpms.remirepo.net）' ;;
    unknown)  printf '未识别（没装 remi-release？）' ;;
    custom:*) printf '自定义（%s）' "${1#custom:}" ;;
  esac
}

show_menu() {
  local cur stream choice ver
  cur=$(current_php_version)
  stream=$(enabled_php_stream)

  log ""
  log "=================================================================="
  log " ${C_B}PHP 升级工具${C_N}   $PRETTY_OS · $PM"
  log "------------------------------------------------------------------"
  log " 当前 PHP : ${cur:-未安装}"
  [ "$PM" = dnf ] && log " module   : ${stream:-<未启用>}"
  [ "$PM" = dnf ] && log " Remi 源  : $(mirror_label "$(current_remi_mirror)")"
  log " 版本升级目标 : ${C_B}PHP $TARGET${C_N}   （默认，可在下一步改）"
  log "=================================================================="
  log "  1) 预演版本升级    换 minor（如 8.4 -> 8.5），只显示会改什么"
  log "  2) 执行版本升级    换 minor，真正执行，会再确认一次"
  log "  3) 安全补丁升级    只升 patch（如 8.5.11 -> 8.5.12），不动分支"
  log "  4) 查看当前状态    版本 / stream / 包数量"
  log "  5) 测源连通性      官方 / 清华 / 中科大，看哪个快"
  log "  6) 切换 Remi 源    官方 / 清华 / 中科大"
  log "  7) 参数说明"
  log "  0) 退出"
  log ""

  while :; do
    drain_input
    printf "请选择 [0-7]: "
    read -r choice || exit 1
    case "$choice" in
      '') continue ;;    # 空回车当刷新，别报错刷屏
      1|2)
        if [ -t 0 ]; then
          if ! pick_version; then
            log "  已取消版本选择"
            continue
          fi
          TARGET="$PICKED"; SUFFIX=${TARGET//./}
        else
          while :; do
            printf "目标版本 [回车 = %s，可选 7.4 8.0-8.5]: " "$TARGET"
            read -r ver || exit 1
            [ -z "$ver" ] && break
            if version_ok "$ver"; then
              TARGET="$ver"; SUFFIX=${TARGET//./}; break
            fi
            bad "'$ver' 不是受支持的版本，可选 7.4 / 8.0–8.5"
          done
        fi
        if [ "$choice" = 2 ]; then MODE="apply"; else MODE="plan"; fi
        log ""
        info "已选: $([ "$MODE" = apply ] && echo '执行' || echo '预演')版本升级 → PHP $TARGET"
        return 0
        ;;
      3) MODE="security"; log ""; info "已选: 安全补丁升级（保持当前分支）"; return 0 ;;
      4) MODE="status"; log ""; return 0 ;;
      5) MODE="nettest"; log ""; return 0 ;;
      6) MODE="mirror"; log ""; return 0 ;;
      7) log ""; usage; log "" ;;
      0|q|Q) log "已退出"; exit 0 ;;
      *) bad "请输入 0-7" ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# 现状
# ---------------------------------------------------------------------------
show_state() {
  step "当前状态"
  if command -v php >/dev/null 2>&1; then
    log "  php: $(php -v 2>/dev/null | head -1)"
  else
    log "  php: 未安装"
  fi

  collect_php_pkgs
  log "  已装 PHP 相关包: ${#PHP_PKGS[@]} 个"

  if [ "$PM" = dnf ]; then
    CUR_STREAM=$(enabled_php_stream)
    log "  module stream: ${CUR_STREAM:-<未启用>}"
  fi

  detect_fpm_unit
  log "  php-fpm 单元: ${FPM_UNIT:-<未安装>}"

  local prov
  prov=$(rpm -q --qf '%{NAME}=%{VERSION}-%{RELEASE}\n' php-cli 2>/dev/null || true)
  [ -n "$prov" ] && log "  php-cli: $prov"
}

# ---------------------------------------------------------------------------
# 备份
# ---------------------------------------------------------------------------
save_backup() {
  BACKUP_DIR="$BACKUP_ROOT/php-upgrade-$TS"
  mkdir -p "$BACKUP_DIR" || die "无法创建备份目录 $BACKUP_DIR"

  step "备份到 $BACKUP_DIR"
  rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 'php*' > "$BACKUP_DIR/rpm-php.txt" 2>/dev/null || true
  rpm -qa > "$BACKUP_DIR/rpm-all.txt" 2>/dev/null || true
  php -v    > "$BACKUP_DIR/php-v.txt"        2>&1 || true
  php -m    > "$BACKUP_DIR/php-m-before.txt" 2>&1 || true
  php --ini > "$BACKUP_DIR/php-ini.txt"      2>&1 || true
  [ -n "$FPM_UNIT" ] && php-fpm -v > "$BACKUP_DIR/php-fpm-v.txt" 2>&1
  cp -a /etc/php.ini       "$BACKUP_DIR/" 2>/dev/null || true
  cp -a /etc/php.d         "$BACKUP_DIR/php.d" 2>/dev/null || true
  cp -a /etc/php-fpm.conf  "$BACKUP_DIR/" 2>/dev/null || true
  cp -a /etc/php-fpm.d     "$BACKUP_DIR/php-fpm.d" 2>/dev/null || true
  "$PM" history list > "$BACKUP_DIR/dnf-history.txt" 2>/dev/null || true
  ok "备份完成"
}

# ===========================================================================
#  通道一：安全补丁（同分支 patch 级，通用，不绑定任何 CVE 编号）
# ===========================================================================
security_channel() {
  local cur curm cand rc before after changed=0 dry=0

  cur=$(current_php_version)
  curm=$(minor_of "$cur")

  step "安全补丁通道（保持分支 $curm，不切 stream）"
  log "  当前版本: $cur"
  cand=$(candidate_php_common)
  log "  仓库最新: ${cand:-<查询失败或超时>}"

  # 分支保护：候选版本若跨 minor，说明这已经是"版本升级"，不能在安全通道里做
  if [ -n "$cand" ]; then
    if [ "$(minor_of "$cand")" != "$curm" ]; then
      bad "仓库最新是 $cand，跨分支（$curm -> $(minor_of "$cand")）"
      log "${C_D}  这是版本升级，不是打补丁。请走: sudo $PROG -v $(minor_of "$cand") --apply${C_N}"
      log "${C_D}  dnf 的 upgrade 不加约束会顺手把 minor 抬上去，本通道拒绝执行。${C_N}"
      return 2
    fi
    if [ "$cand" = "$cur" ]; then
      info "仓库没有比 $cur 更新的包 —— 当前分支暂无新补丁"
      log "${C_D}  仓库同步有延迟时属正常；可稍后重跑本命令，或用 --min-version 断言合规基线。${C_N}"
    else
      ok "可升级: $cur -> $cand（同分支）"
    fi
  fi

  if [ -n "$MIN_VERSION" ]; then
    if ver_ge "$cur" "$MIN_VERSION"; then
      ok "当前 $cur 已满足基线 >= $MIN_VERSION"
    else
      warn "当前 $cur 低于基线 $MIN_VERSION，本次升级后需再次校验"
    fi
  fi

  # 预演
  if [ "$ASSUME_YES" != 1 ] && { [ "$MODE" = security ] && [ ! -t 0 ]; }; then
    dry=1
  fi
  if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
    log ""
    if [ -n "$cand" ] && [ "$cand" != "$cur" ]; then
      printf "升级 PHP %s -> %s 并重启 php-fpm？[y/N] " "$cur" "$cand"
    else
      printf "仍要执行一次安全补丁流程（可能无事可做）？[y/N] "
    fi
    read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) log "已取消"; return 0 ;; esac
  fi
  if [ "$dry" = 1 ]; then
    info "非交互环境且未加 -y，只做检查，不执行"
    # 只检查也要给 CI 一个明确退出码
    if [ -n "$MIN_VERSION" ] && ! ver_ge "$cur" "$MIN_VERSION"; then
      bad "当前 $cur 低于基线 $MIN_VERSION"
      return 1
    fi
    return 0
  fi

  save_backup
  PREV_HIST=$(history_last_id)
  log "  变更前事务 ID: ${PREV_HIST:-n/a}"

  local snap_before
  snap_before=$(php_pkg_snapshot)

  # 优先走安全元数据；Remi 这类社区仓库没有 errata，退回普通 patch 升级
  # （分支保护已在上方做过，候选版本跨 minor 时根本走不到这里）
  # 优先走安全元数据；社区仓库（如 Remi）没有 errata，--security 会“什么都没选中但返回 0”，
  # 所以这里按「版本有没有变」判断，而不是看退出码。
  # 分支保护已在上方做过，候选跨 minor 时走不到这里，普通 upgrade 不会抬 minor。
  if [ "$PM" = dnf ]; then
    "$PM" "${REPO_ARGS[@]}" -y upgrade --security 'php*'
    if [ "$(php_pkg_snapshot)" = "$snap_before" ] && [ -n "$cand" ] && [ "$cand" != "$cur" ]; then
      warn "--security 没选中任何包（社区仓库通常无 errata 元数据），改用普通 patch 升级"
      "$PM" "${REPO_ARGS[@]}" -y upgrade 'php*'
    fi
  else
    "$PM" "${REPO_ARGS[@]}" -y --security update 'php*' \
      || "$PM" "${REPO_ARGS[@]}" -y update 'php*'
  fi

  after=$(current_php_version)
  [ "$after" != "$cur" ] && changed=1

  # 兜底：确保 redis 扩展也跟上（它只是 php-pecl-redis6 的 Provides）
  if [ "$changed" = 1 ] && pkg_has_candidate php-pecl-redis6; then
    "$PM" "${REPO_ARGS[@]}" -y install php-pecl-redis6 >/dev/null 2>&1 || true
  fi

  # 一个包都没动就不重启：线上环境不允许无谓重启
  if [ "$(php_pkg_snapshot)" = "$snap_before" ]; then
    step "服务"
    info "本次没有实际变更，跳过重启；php-fpm 保持原状"
  else
    reload_services
  fi

  step "结果"
  log "  $cur -> $after"
  if [ "$changed" = 1 ]; then
    ok "已应用补丁"
  else
    info "版本未变，说明本分支暂无新包"
  fi

  local fail=0
  if [ "$(minor_of "$after")" != "$curm" ]; then
    bad "分支被意外从 $curm 改成了 $(minor_of "$after")"; fail=1
  else
    ok "分支保持 $curm"
  fi
  if [ -n "$MIN_VERSION" ]; then
    if ver_ge "$after" "$MIN_VERSION"; then ok "满足基线 >= $MIN_VERSION"
    else bad "仍未达到基线 $MIN_VERSION（当前 $after）"; fail=1; fi
  fi
  if [ -n "$FPM_UNIT" ]; then
    php-fpm -t >/dev/null 2>&1 && ok "php-fpm 配置语法正常" \
      || { bad "php-fpm -t 失败"; fail=1; }
    command -v php-fpm >/dev/null 2>&1 || warn "找不到 php-fpm 命令"
  fi

  if [ "$fail" -ne 0 ]; then
    rollback
    return 1
  fi
  return 0
}

# ===========================================================================
#  通道二：版本升级（换 minor）
# ===========================================================================
check_target_available() {
  local cand
  step "目标分支可得性"
  info "查 php-common 候选版本（只读 remi 仓库，最多 60s；超时则跳过本项检查）"
  cand=$(candidate_php_common)
  log "  仓库最新 php-common: ${cand:-<查询失败或超时>}"

  if [ -z "$cand" ]; then
    warn "查不到候选版本：网络慢、镜像同步延迟，或 ${REPO_ARGS[*]} 未真正启用"
    warn "这项只是预检，跳过不影响后续；实际升级时 dnf 会自己算依赖并给出结论"
    return 1
  fi
  case "$cand" in
    "$TARGET".*) ok "仓库已提供 PHP $TARGET（$cand）"; return 0 ;;
    *)
      bad "仓库最新为 $cand，不是 $TARGET 分支"
      log "${C_D}  常见原因：remi-release 太旧（不认 php:remi-$TARGET）→ $PM update remi-release -y${C_N}"
      log "${C_D}  或该 el${EL_MAJOR} 版本已不再由 Remi 构建 $TARGET${C_N}"
      return 1
      ;;
  esac
}

switch_stream() {
  if [ "$PM" != dnf ]; then
    info "yum 环境无 module 概念，直接用 remi-php${SUFFIX} 仓库升级"
    return 0
  fi

  if [ "$CUR_STREAM" = "remi-$TARGET" ]; then
    ok "已处于 php:remi-$TARGET，跳过 stream 切换（只做分支内升级）"
    return 0
  fi

  step "切换 module stream: ${CUR_STREAM:-<无>} -> remi-$TARGET"

  if [ "$MODE" != apply ]; then
    log "  将执行: $PM module reset php -y"
    log "           $PM module enable php:remi-$TARGET -y ${REPO_ARGS[*]}"
    log "           $PM distro-sync 'php*'   # 换 stream 后必须 distro-sync 对齐"
    return 0
  fi

  PREV_HIST=$(history_last_id)
  log "  变更前事务 ID: ${PREV_HIST:-n/a}"

  "$PM" module reset php -y >/dev/null 2>&1 \
    || die "module reset 失败，系统未改动，安全退出"

  "$PM" "${REPO_ARGS[@]}" module enable "php:remi-$TARGET" -y >/dev/null 2>&1 \
    || die "module enable php:remi-$TARGET 失败（remi-release 可能太旧：$PM update remi-release -y）"

  CUR_STREAM="remi-$TARGET"
  STREAM_CACHE="remi-$TARGET"
  ok "stream 已切到 php:remi-$TARGET"
}

upgrade_packages() {
  step "升级 PHP 包（通配 php*，不逐个列包名）"

  if [ "$MODE" != apply ]; then
    log "  预演输出（--assumeno，会中止，不落地）:"
    timeout 300 "$PM" "${REPO_ARGS[@]}" --setopt=timeout=30 --setopt=retries=1 \
      upgrade --assumeno 'php*' 2>&1 | sed 's/^/    /' | head -50
    log ""
    log "${C_D}  重点看 php-common 的版本变化：跨 minor 就是换分支，不是打补丁${C_N}"
    return 0
  fi

  local rc=0
  if [ "$PM" = dnf ] && [ -n "$CUR_STREAM" ]; then
    # 实时输出：dnf 自己的进度条能证明它没死，别再拿 tail 把过程吞掉
    "$PM" "${REPO_ARGS[@]}" -y distro-sync 'php*'
    rc=$?
  else
    "$PM" "${REPO_ARGS[@]}" -y update 'php*'
    rc=$?
  fi
  [ "$rc" -eq 0 ] || die "升级失败（rc=$rc）"

  # php-redis 在 Remi 里只是 php-pecl-redis6 的 Provides，按名字匹配容易解析不到
  if pkg_has_candidate php-pecl-redis6; then
    "$PM" "${REPO_ARGS[@]}" -y install php-pecl-redis6 >/dev/null 2>&1 \
      && ok "php-pecl-redis6 就位" || warn "php-pecl-redis6 未成功，需人工确认"
  fi

  # imap / pspell 自 PHP 8.4 起移出内核，改为 PECL 包
  case "$TARGET" in
    8.4|8.5)
      if pkg_has_candidate php-pecl-imap; then
        "$PM" "${REPO_ARGS[@]}" -y install php-pecl-imap >/dev/null 2>&1 \
          && ok "php-pecl-imap 就位（8.4+ 已移出内核）"
      fi
      ;;
  esac

  ok "PHP 包升级完成"
}

# ---------------------------------------------------------------------------
# imagick：im7 优先；仓库没有才考虑 im6，绝不因安装失败就偷偷降级
# ---------------------------------------------------------------------------
handle_imagick() {
  [ "$IMAGICK_MODE" = never ] && return 0

  local has_im6=0 installed=0
  rpm -qa 'php-pecl-imagick*' 2>/dev/null | grep -q . && installed=1
  rpm -q php-pecl-imagick-im6 >/dev/null 2>&1 && has_im6=1

  if [ "$IMAGICK_MODE" = auto ] && [ "$installed" -eq 0 ]; then
    info "未装 imagick，跳过（要装加 --imagick）"
    return 0
  fi

  step "处理 php-pecl-imagick"
  # 模块流里的包名就是 php-pecl-imagick（内置 IM7），优先用它，升级路径最干净；
  # php-pecl-imagick-im7 / -im6 是并行 SCL 场景的命名
  if pkg_has_candidate php-pecl-imagick; then
    if [ "$MODE" = apply ]; then
      "$PM" "${REPO_ARGS[@]}" -y install php-pecl-imagick >/dev/null 2>&1 \
        && ok "php-pecl-imagick 已升级（模块流原生包，内置 ImageMagick 7）" \
        || die "php-pecl-imagick 安装失败，请手工排查"
    else
      log "  将升级 php-pecl-imagick（模块流原生包）"
    fi
  elif pkg_has_candidate php-pecl-imagick-im7; then
    if [ "$has_im6" -eq 1 ]; then
      warn "已装 imagick-im6；im6 -> im7 需先 remove 再 install（两者都 Provide php-pecl(imagick)）"
      warn "手动: $PM remove -y php-pecl-imagick-im6 && $PM ${REPO_ARGS[*]} install -y php-pecl-imagick-im7"
      return 0
    fi
    if [ "$MODE" = apply ]; then
      "$PM" "${REPO_ARGS[@]}" -y install php-pecl-imagick-im7 >/dev/null 2>&1 \
        && ok "imagick (ImageMagick 7) 已升级" \
        || die "imagick-im7 安装失败，请手工排查（不会自动降级 im6，避免镜像库依赖冲突）"
    else
      log "  将安装/升级 php-pecl-imagick-im7"
    fi
  elif pkg_has_candidate php-pecl-imagick-im6; then
    warn "目标仓库无 im7 构建，改用 im6"
    [ "$MODE" = apply ] && "$PM" "${REPO_ARGS[@]}" -y install php-pecl-imagick-im6 >/dev/null 2>&1
  else
    warn "仓库里没有 imagick 构建，跳过"
  fi
}

# ---------------------------------------------------------------------------
# 重启服务
# ---------------------------------------------------------------------------
reload_services() {
  step "重启服务（OPcache 在进程内存里，不重启等于没升级）"
  systemctl daemon-reload >/dev/null 2>&1 || true

  if [ -n "$FPM_UNIT" ]; then
    if systemctl is-active --quiet "$FPM_UNIT"; then
      systemctl restart "$FPM_UNIT" && ok "$FPM_UNIT 已重启" \
        || warn "$FPM_UNIT 重启失败，看 journalctl -u $FPM_UNIT -n 80"
    else
      info "$FPM_UNIT 未运行，跳过"
    fi
  fi

  systemctl is-active --quiet httpd 2>/dev/null && systemctl reload httpd >/dev/null 2>&1 && ok "httpd 已 reload"
  systemctl is-active --quiet nginx 2>/dev/null && systemctl reload nginx >/dev/null 2>&1 && ok "nginx 已 reload"
}

# ---------------------------------------------------------------------------
# 升级后校验
# ---------------------------------------------------------------------------
# 从包名/Release 判断它属于哪个 PHP 分支；返回空表示与分支无关
branch_of() {
  local name=$1 rel=$2 b=""
  case "$name" in
    php[0-9][0-9]-*)                      # 并行 SCL：php85-php-cli
      b=${name:3:2}
      printf '%s.%s' "${b:0:1}" "${b:1:1}"
      return 0
      ;;
  esac
  case "$rel" in
    *module_php.*)
      b=$(printf '%s' "$rel" | sed -n 's/.*module_php\.\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
      ;;
    *.remi.*)
      b=$(printf '%s' "$rel" | sed -n 's/.*\.remi\.\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
      ;;
  esac
  printf '%s' "$b"
}

verify() {
  step "校验"
  local fail=0 v fv
  collect_php_pkgs

  v=$(current_php_version)
  if [ -n "$v" ]; then
    case "$v" in
      "$TARGET".*) ok "CLI 版本 $v" ;;
      *) warn "CLI 版本 $v，期望 $TARGET.x"; fail=1 ;;
    esac
  else
    warn "php 命令不可用"; fail=1
  fi

  if [ -n "$FPM_UNIT" ] && command -v php-fpm >/dev/null 2>&1; then
    fv=$(php-fpm -v 2>/dev/null | head -1 | awk '{ print $2 }')
    case "$fv" in
      "$TARGET".*) ok "FPM 版本 $fv" ;;
      *) warn "FPM 版本 ${fv:-未知}，期望 $TARGET.x（CLI/FPM 不一致会导致诡异问题）"; fail=1 ;;
    esac
  fi

  if [ -n "$MIN_VERSION" ]; then
    if ver_ge "$v" "$MIN_VERSION"; then ok "满足基线 >= $MIN_VERSION"
    else bad "未达到基线 $MIN_VERSION（当前 ${v:-未知}）"; fail=1; fi
  fi

  # 判断每个包是为哪个 PHP 分支构建的：
  #   模块流  php-pecl-apcu-5.1.28-1.module_php.8.5.el9.remi
  #   EL7    php-pecl-apcu-5.1.28-1.el7.remi.8.5
  #   SCL    php85-php-cli-...
  # 纯 PHP 库（noarch、版本与分支无关，如 php-nikic-php-parser5、php-fedora-autoloader、
  # php-pear）的 release 里没有分支号，返回空 → 不参与一致性判断，避免误报。
  LEFTOVER=()
  if [ ${#PHP_PKGS[@]} -gt 0 ]; then
    local pkg name ver rel br
    for pkg in "${PHP_PKGS[@]}"; do
      read -r name ver rel <<<"$(rpm -q --qf '%{NAME} %{VERSION} %{RELEASE}' "$pkg" 2>/dev/null)"
      [ -n "${name:-}" ] || continue
      br=$(branch_of "$name" "$rel")
      [ -z "$br" ] && continue
      [ "$br" = "$TARGET" ] || LEFTOVER+=("$name $ver-$rel  (构建分支 $br)")
    done
  fi

  if [ ${#LEFTOVER[@]} -gt 0 ]; then
    warn "以下包仍是为别的 PHP 分支构建的（多半是没跟上升级的扩展）："
    printf '    - %s\n' "${LEFTOVER[@]}"
    warn "确认业务不需要后: $PM remove -y <包名>；或安装对应分支的 PECL 包"
    fail=1
  else
    ok "所有 php 包都对应当前分支 $TARGET"
  fi

  # 扩展丢失检测（8.4 起 imap/pspell 移出内核，最容易踩）
  if [ -f "$BACKUP_DIR/php-m-before.txt" ]; then
    php -m 2>/dev/null | sort > "$BACKUP_DIR/php-m-after.txt"
    LOST_EXT=()
    while IFS= read -r e; do LOST_EXT+=("$e"); done < <(
      comm -23 <(sort -u "$BACKUP_DIR/php-m-before.txt") <(sort -u "$BACKUP_DIR/php-m-after.txt") \
        | grep -v '^\[PHP Modules\]$'
    )
    if [ ${#LOST_EXT[@]} -gt 0 ]; then
      warn "扩展丢失: ${LOST_EXT[*]}（8.4 起 imap/pspell 等需改用 PECL 包）"
    else
      ok "扩展无丢失"
    fi
  fi

  if [ -n "$FPM_UNIT" ]; then
    if php-fpm -t >/dev/null 2>&1; then
      ok "php-fpm 配置语法正常"
    else
      bad "php-fpm -t 失败"
      php-fpm -t 2>&1 | sed 's/^/    /'
      fail=1
    fi
  fi

  local f
  for f in /etc/php.ini /etc/php-fpm.conf; do
    [ -f "$f.rpmnew" ] && warn "存在 $f.rpmnew，请 diff 后手工合并"
  done

  return "$fail"
}

rollback() {
  step "回滚"
  if [ -z "$PREV_HIST" ]; then
    warn "未记录变更前事务 ID，无法自动回滚；备份见 ${BACKUP_DIR:-无}"
    return 1
  fi
  if [ "$ASSUME_YES" = 1 ]; then
    warn "自动回滚到事务 $PREV_HIST ..."
    "$PM" history rollback "$PREV_HIST" -y 2>&1 | tail -12
    reload_services || true
  else
    warn "手动回滚: $PM history rollback $PREV_HIST"
    warn "（$PM history list 查 ID；$PM history undo <ID> 只撤销最后一笔）"
  fi
}

# ---------------------------------------------------------------------------
# 版本升级执行入口
# ---------------------------------------------------------------------------
version_channel() {
  show_state
  check_target_available || true

  if [ "$MODE" != apply ]; then
    switch_stream
    upgrade_packages
    handle_imagick
    log ""
    log "${C_Y}预演结束，系统未改动。${C_N}"
    log "确认无误后执行: sudo $PROG -v $TARGET --apply"
    log "${C_D}只想打安全补丁、不换分支: sudo $PROG --security${C_N}"
    return 0
  fi

  if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
    log ""
    # 分支没变的时候，别再说"升级到 X"——那会让人以为要跨大版本。
    # 实测踩过的场景：已在 remi-8.5，还提示"即将把 PHP 升级到 8.5"。
    if [ "$PM" = dnf ] && [ "$CUR_STREAM" = "remi-$TARGET" ]; then
      info "当前已在 PHP $TARGET 分支（stream: $CUR_STREAM），本次只是分支内的小版本更新"
      warn "即将更新 PHP $TARGET 及其扩展到仓库中的最新版本（$PRETTY_OS）"
    else
      warn "即将把 PHP 升级到 $TARGET（$PRETTY_OS），当前 stream: ${CUR_STREAM:-<无>}"
    fi
    printf "继续？[y/N] "
    read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) warn "已取消，系统未改动"; return 0 ;; esac
  fi

  save_backup
  PREV_HIST=$(history_last_id)
  log "  变更前事务 ID: ${PREV_HIST:-n/a}"
  local snap_before
  snap_before=$(php_pkg_snapshot)

  switch_stream
  upgrade_packages
  handle_imagick

  # 一个包都没动就不要重启：线上服务重启是有代价的
  if [ "$(php_pkg_snapshot)" = "$snap_before" ]; then
    step "服务"
    info "本次没有实际变更（dnf 报 Nothing to do），跳过重启；php-fpm 保持原状"
  else
    reload_services
  fi

  if verify; then
    log ""
    ok "升级完成：PHP $TARGET"
    [ "$PM" = dnf ] && log "  锁定分支防止误跨版本: $PM versionlock add 'php*'   # 需 dnf-plugins-core"
    log "  备份: $BACKUP_DIR"
    return 0
  fi

  log ""
  bad "校验未全通过，详见上方 WARN"
  rollback
  return 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
preflight_light

# ---- 非交互：一次性执行（脚本 / CI 用） ----
if [ "$INTERACTIVE" != 1 ]; then
  case "$MODE" in
    status)  show_state; exit 0 ;;
    nettest) nettest_action; exit 0 ;;
    mirror)  apply_mirror "$MIRROR"; exit 0 ;;
  esac
  ensure_repos
  detect_fpm_unit
  case "$MODE" in
    security) show_state; security_channel; exit $? ;;
    *)        version_channel; exit $? ;;
  esac
fi

# ---- 交互：菜单循环，动作做完回到菜单 ----
while :; do
  MODE="plan"
  MIRROR=""
  show_menu

  case "$MODE" in
    status)
      show_state
      ;;
    nettest)
      nettest_action
      ;;
    mirror)
      # 注意：main 在函数外，不能用 local
      CURM=$(current_remi_mirror)
      M_LBL=("1) 官方   rpms.remirepo.net" "2) 清华   mirrors.tuna.tsinghua.edu.cn" "3) 中科大 mirrors.ustc.edu.cn")
      M_KEY=(official tuna ustc)
      log ""
      log "  ${C_D}当前使用: $(mirror_label "$CURM")${C_N}"
      log ""
      log "  ${C_B}选择要使用的 Remi 源${C_N}"
      for MI in 0 1 2; do
        if [ "${M_KEY[$MI]}" = "$CURM" ]; then
          log "    ${M_LBL[$MI]}   ${C_G}← 当前${C_N}"
        else
          log "    ${M_LBL[$MI]}"
        fi
      done
      log "    0) 返回"
      drain_input
      printf "请选择 [0-3]: "
      read -r mc || exit 0
      case "$mc" in
        1) apply_mirror official ;;
        2) apply_mirror tuna ;;
        3) apply_mirror ustc ;;
        *) info "已返回" ;;
      esac
      ;;
    security)
      ensure_repos
      detect_fpm_unit
      show_state
      security_channel
      ;;
    *)
      ensure_repos
      detect_fpm_unit
      version_channel
      ;;
  esac

  # 管道/重定向进来的输入没法继续交互，直接收工，避免空转
  if [ ! -t 0 ]; then
    exit 0
  fi
  log ""
  drain_input
  printf '%s—— 按回车返回菜单，Ctrl-C 退出 ——%s\n' "$C_D" "$C_N"
  read -r _ || exit 0
done
