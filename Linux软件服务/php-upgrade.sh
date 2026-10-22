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
#        --mirror-epel <源> 切换 EPEL 源：official | tuna | ustc | aliyun | huawei
#        --mirror-os <源>   切换官方源：tencent | tuna | ustc | aliyun | huawei | official
#        --audit            系统源体检：逐个测速 + 查重复 repo 定义
#        --rc               允许升级到 RC（remi-modular-test）。默认只报不装，
#                           装不装由你决定；Remi 官方标注 RC 不适合生产
#    -y, --yes              无人值守：不再确认，失败自动回滚
#        --imagick          强制安装/升级 php-pecl-imagick（im7 优先）
#        --no-imagick       完全跳过 imagick
#        --menu             强制进入交互菜单
#    -h, --help             显示本帮助
#
#  菜单项:
#    升级    1 执行升级   2 预演升级   3 安全补丁
#    源管理  4 切换源（Remi/EPEL/官方，进入即实测）+ 全面体检
#    其他    5 当前状态   6 参数说明   0 退出
# =============================================================================

set -uo pipefail

ARG_COUNT=$#
PROG=${0##*/}
SCRIPT_VER="build-20261022-0040"   # 用于确认手上跑的是不是最新一份

TARGET=${PHP_TARGET_VERSION:-8.5}
MODE="plan"              # plan | apply | security | status
INTERACTIVE=0
ASSUME_YES=0
MIN_VERSION=""           # 通用合规基线，如 8.5.12
IMAGICK_MODE="auto"      # auto=仅在已装时升级 | always | never
# 是否允许升级到 RC（remi-modular-test）。默认 0：只报不装，装不装由用户显式决定。
# Remi 的 RC 通知里明确写着不适合生产，所以绝不能默认开。
USE_RC=0
RC_VALUE=""              # 测试仓库里的 RC 版本号，如 8.5.12~RC1
RC_CHECKED=0
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
PROBE_ERR=""            # run_probe 收集的 stderr，失败时用来诊断
NET_CHECKED=""
NET_RC=0
MIRROR=""
MIRROR_KIND="remi"        # remi | epel | os —— 决定 --mirror 改哪一类源
SYS_EPEL_HOST=""
SYS_EPEL_ROOT=""
SYS_OS_HOST=""
SYS_OS_ROOT=""
SYS_OS_PREFIX=""
PHP_SCOPE_ARGS=()
# 系统源作用域（--disablerepo/--enablerepo 组合），由 build_scope_args 生成
SCOPE_ARGS=()
STREAM_CACHE=""
# 现场测速结果缓存：bench_candidates 把 "key<TAB>耗时秒" 逐行写进来，
# 菜单据此标注"本机实测最快"，而不是写死开发机上的结论。
BENCH_KEYS=()
BENCH_TIMES=()
BENCH_DONE=0
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
#
# minrate 是关键：dnf 在下载速度持续低于该值（字节/秒）时会直接放弃这个
# 源并报错，而不是傻等。实测 EPEL 走官方 metalink 时只有 11 kB/s，
# 进度条显示 "30:33 E"（超时失败）——minrate 让它几秒内就跳过。
RO_OPTS=(--setopt=assumeyes=True --setopt=timeout=30 --setopt=retries=1 \
         --setopt=minrate=1024 --setopt=skip_if_unavailable=False)
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
    --mirror-epel)   [ $# -ge 2 ] || die "$1 需要参数"; MIRROR="$2"; MODE="mirror-epel"; shift 2 ;;
    --mirror-os)     [ $# -ge 2 ] || die "$1 需要参数"; MIRROR="$2"; MODE="mirror-os"; shift 2 ;;
    --audit)         MODE="audit"; shift ;;
    --rc)            USE_RC=1; shift ;;
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
  # 只有用户显式 --rc 才把测试仓库纳进来。默认只用稳定仓库，
  # 避免 dnf 自作主张把 RC 推给生产机。
  if [ "$USE_RC" = 1 ]; then
    want+=(remi-modular-test remi-test "remi-php${SUFFIX}-test")
  fi
  for r in "${want[@]}"; do
    printf '%s\n' "$avail" | grep -qx "$r" && REPO_ARGS+=("--enablerepo=$r")
  done
  [ ${#REPO_ARGS[@]} -gt 0 ] || return 1
  # 探测类查询只加载 remi 仓库：php 包都在这里，
  # 关掉 baseos/appstream 能少下几十 MB 元数据，是"卡住"的主因
  PROBE_ARGS=(--disablerepo='*' "${REPO_ARGS[@]}")
  return 0
}

# 系统源作用域：只加载 PHP 升级真正需要的仓库，其余全部 --disablerepo 掉。
# 结果写入全局数组 SCOPE_ARGS（不用 nameref：bash 4.2 的 RHEL 7/8 不支持 local -n）。
#
# 为什么必须加：makecache 默认拉**所有** enabled 仓库的元数据。实测一台腾讯云
# CentOS Stream 9 上，Aeris(~6 kB/s)、ELRepo、epel-next、腾讯云源加起来就够等一两分钟，
# 而其中没有一个装PHP 需要的包。白名单里放 EPEL 是因为部分 php-* 依赖它。
SCOPE_ARGS=()
build_scope_args() {
  SCOPE_ARGS=()
  local avail r
  avail=$(timeout "$RO_TIMEOUT" "$PM" "${RO_OPTS[@]}" repolist --all 2>/dev/null | awk 'NR>1 {print $1}')
  [ -n "$avail" ] || return 1

  local want=(baseos appstream crb extras-common epel
              remi remi-safe remi-modular "remi-php${SUFFIX}")
  local -a keep=()
  for r in "${want[@]}"; do
    printf '%s\n' "$avail" | grep -qx "$r" && keep+=("$r")
  done
  [ ${#keep[@]} -gt 0 ] || return 1

  SCOPE_ARGS=(--disablerepo='*' "${keep[@]/#/--enablerepo=}")
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
  local out errf pid rc=0 t=0 start elapsed soft grace
  start=$(date +%s)
  # soft + grace 必须正好等于 limit，否则小预算时总时长会翻倍
  if [ "$limit" -gt 20 ]; then
    grace=10; soft=$((limit - 10))
  else
    grace=1; soft=$((limit - 1))
  fi
  [ "$soft" -lt 1 ] && soft=1
  out=$(mktemp) || return 1
  errf=$(mktemp) || { rm -f "$out"; return 1; }
  PROBE_ERR=""
  # stderr 收集到 PROBE_ERR 而不是丢弃：失败时得知道为什么失败，
  # 否则用户只看到"makecache 未完成"，看不出是 404 还是仓库名不认。
  ( timeout -k "$grace" "$soft" "$@" >"$out" 2>"$errf" ) &
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
  PROBE_ERR=$(cat "$errf" 2>/dev/null)
  cat "$out"
  rm -f "$out" "$errf"
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
  raw=$(query_pkg_version "$1")
  [ -n "$raw" ]
}

# 查某个包在仓库里的最新版本。返回版本号（如 8.5.12），查不到返回空。
#
# 为什么不用 `dnf -q list --available`：
#   1) `-q` 在部分 dnf 版本里是"完全静默"，连包列表都不打，解析就拿到空；
#   2) `list` 的输出格式随 dnf 版本/locale 变（列对齐、列顺序），靠 awk 切列很脆；
#   3) 查不到时原样只说"失败或超时"，根本看不出是网络问题还是解析问题。
# 改成：优先 `repoquery --queryformat`（确定性单行输出），失败再退回 `list`，
# 两条路都不通就把原始输出打出来 —— 没有诊断信息的失败等于没查。
query_pkg_version() {   # $1=包名
  local pkg=$1 raw v
  PROBE_LABEL="查询 $pkg 候选版本"

  # 路线 1：repoquery 直接给出格式化结果，不需要解析列
  if command -v "$PM" >/dev/null 2>&1; then
    v=$(run_probe 60 "$PM" "${RO_OPTS[@]}" "${PROBE_ARGS[@]}" \
          repoquery --queryformat '%{VERSION}\n' --latest-limit 1 "$pkg" 2>/dev/null \
          | grep -E '^[0-9]' | tail -1)
    if [ -n "$v" ]; then
      PROBE_LABEL=""
      printf '%s' "$v"
      return 0
    fi
  fi

  # 路线 2：退回 list --available（不加 -q，避免被静默）
  raw=$(run_probe 60 "$PM" "${RO_OPTS[@]}" "${PROBE_ARGS[@]}" list --available "$pkg")
  # 只认精确包名（`php-common` 或 `php-common.x86_64`）。
  # 注意 awk 字符串里必须写 "\\\\." 才是正则里的转义点：写成 "\." 会被 awk
  # 解析成 "."（匹配任意字符），于是 php-common-devel 也匹配上了。
  # 同样不能用 `^php-common[.-]`，那也放得进 -devel。
  v=$(printf '%s\n' "$raw" | awk -v p="$pkg" '
        $1 == p || $1 ~ ("^" p "\\.") {
          for (i=1;i<=NF;i++) if ($i ~ /^[0-9]/ && $i ~ /[-.]/) { print $i; exit }
        }
      ' | cut -d- -f1)

  PROBE_LABEL=""
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return 0
  fi

  # 两条路都不通：把原始输出留下来，否则用户只知道"失败"，不知道为什么
  if [ -n "$raw" ]; then
    warn "$pkg 查询有输出但没解析出版本号，原始输出如下："
    printf '%s\n' "$raw" | sed 's/^/      /' | head -12
  else
    warn "$pkg 查询完全没有输出，可能原因："
    warn "  1) 仓库作用域里的仓库名不被 dnf 认可（检查上面是否打印 No repository match）"
    warn "  2) 该包不在当前作用域的仓库里"
    warn "  3) 元数据太旧，看不到新版本: sudo $PM makecache --refresh"
  fi
  return 1
}

# 仓库里 php-common 的最新版本（判断"目标分支有没有货 / 有没有新补丁"）
# 带缓存：菜单里反复预演不会每次都去问一遍仓库
candidate_php_common() {
  if [ -n "$CAND_SUFFIX" ] && [ "$CAND_SUFFIX" = "$SUFFIX" ]; then
    printf '%s' "$CAND_VALUE"
    return 0
  fi
  local v
  v=$(query_pkg_version php-common) || v=""
  if [ -n "$v" ]; then
    CAND_SUFFIX="$SUFFIX"
    CAND_VALUE="$v"
  fi
  printf '%s' "$v"
}

# 测试仓库（remi-modular-test / remi-test）里的 RC 版本。
#
# 为什么单独查：RC 在**测试仓库**，和稳定仓库不是一回事。
# 用户在 Remi 博客上看到的 "8.5.12" 很可能是 8.5.12RC1（10-09 发的测试包），
# 而稳定仓库最高只有 8.5.11 —— 之前只查稳定仓库就误判成"Remi 没发布过 8.5.12"。
#
# 返回形如 `8.5.12~RC1` 的完整版本号（注意 `~`：RPM 里表示"低于同版本正式版"）。
# 只报不装：是否升 RC 由用户显式决定（USE_RC / --rc）。
candidate_rc_php_common() {
  if [ "$RC_CHECKED" = 1 ]; then
    printf '%s' "$RC_VALUE"
    return 0
  fi
  RC_CHECKED=1
  local v raw
  # 只开测试仓库，别把稳定仓库混进来（否则会返回 8.5.11 而不是 RC）
  local -a test_scope=(--disablerepo='*')
  local avail r
  avail=$(timeout "$RO_TIMEOUT" "$PM" "${RO_OPTS[@]}" repolist --all 2>/dev/null \
            | awk 'NR > 1 { print $1 }' | sort -u)
  for r in remi-modular-test remi-test "remi-php${SUFFIX}-test"; do
    printf '%s\n' "$avail" | grep -qx "$r" && test_scope+=("--enablerepo=$r")
  done
  # 测试仓库一个都没识别出来：直接返回空，别拿稳定仓库的数据冒充 RC
  [ ${#test_scope[@]} -gt 1 ] || { RC_VALUE=""; printf ''; return 0; }

  PROBE_LABEL="查询测试仓库 RC 版本"
  raw=$(run_probe 60 "$PM" "${RO_OPTS[@]}" "${test_scope[@]}" \
          repoquery --queryformat '%{VERSION}\n' --latest-limit 1 php-common 2>/dev/null \
          | grep -E '^[0-9]' | tail -1)
  PROBE_LABEL=""

  if [ -z "$raw" ]; then
    raw=$(run_probe 60 "$PM" "${RO_OPTS[@]}" "${test_scope[@]}" list --available php-common)
    raw=$(printf '%s\n' "$raw" | awk -v p="php-common" '
            $1 == p || $1 ~ ("^" p "\\.") {
              for (i=1;i<=NF;i++) if ($i ~ /^[0-9]/ && $i ~ /[-.]/) { print $i; exit }
            }' | cut -d- -f1)
  fi

  # 只认带 RC 标记的，避免把稳定版混进来
  case "$raw" in
    *RC*|*rc*|*alpha*|*beta*|*~*) v="$raw" ;;
    *) v="" ;;
  esac
  RC_VALUE="$v"
  printf '%s' "$v"
}

# 把版本号里的 RC 标记提出来给人看：8.5.12~RC1 -> RC1
rc_tag_of() {
  printf '%s' "$1" | grep -oiE '(rc[0-9]*|alpha[0-9]*|beta[0-9]*)$' | tr '[:upper:]' '[:lower:]'
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

# 本次升级的目标版本号：选了 RC 就用 RC，否则用稳定仓库最新。查不到返回空。
target_php_version() {
  if [ "$USE_RC" = 1 ] && [ -n "$RC_VALUE" ]; then
    printf '%s' "$RC_VALUE"
    return 0
  fi
  candidate_php_common
}

# 版本完全一致就别走事务 —— 线上尤其不能"没有变化也重启一遍服务"。
# 返回 0 = 确实有变化要升；1 = 已是最新（调用方应跳过）；
# 拿不到版本信息时返回 0（不挡，交给 dnf 自己判断）。
php_upgrade_needed() {
  local cur tgt
  cur=$(current_php_version)
  tgt=$(target_php_version)
  [ -n "$cur" ] && [ -n "$tgt" ] || return 0
  [ "$cur" != "$tgt" ]
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

# ── 候选镜像现场测速 ──────────────────────────────────────────────────
# 为什么必须现场测而不是写死"XX 最快"：
#   最优镜像取决于机器所在地区、运营商、时段，一台机器上测出的结论搬到
#   另一台就是错的。之前把"阿里云实测最快"硬编码进菜单，用户在另一台机器上
#   看到的是未经测量的断言。改成：进入菜单先实测（每个最多 6s），把结果
#   和"最快"标记一起显示。
#
# bench_one <key> <url>   —— 结果写入 BENCH_TIMES（不可达则为空）
bench_one() {
  local key=$1 url=$2 t
  BENCH_KEYS+=("$key")
  BENCH_TIMES+=("")
  if t=$(curl -fsS -o /dev/null --connect-timeout 3 --max-time 6 \
           -w '%{time_total}' "$url" 2>/dev/null); then
    BENCH_TIMES[${#BENCH_TIMES[@]}-1]="$t"
  fi
}

# 取某个候选的实测耗时（秒，最多 4 位小数）；不可达返回空
bench_get() {
  local key=$1 i
  for i in "${!BENCH_KEYS[@]}"; do
    [ "${BENCH_KEYS[$i]}" = "$key" ] && { printf '%s' "${BENCH_TIMES[$i]}"; return 0; }
  done
  return 1
}

# 本机实测最快的 key（只在有成功结果时返回）
bench_fastest() {
  local i best="" bt=""
  for i in "${!BENCH_KEYS[@]}"; do
    [ -n "${BENCH_TIMES[$i]}" ] || continue
    if [ -z "$bt" ] || awk "BEGIN{exit !(${BENCH_TIMES[$i]} < $bt)}"; then
      bt="${BENCH_TIMES[$i]}"; best="${BENCH_KEYS[$i]}"
    fi
  done
  [ -n "$best" ] && printf '%s' "$best"
}

# 打印一行候选菜单：<行号> <名称> <key> <url> <当前key>
# 实测数据 + "本机最快"标记 + "← 当前"标记，全部来自现场测速结果。
bench_menu_line() {
  local num=$1 name=$2 key=$3 url=$4 cur=$5 t mark
  t=$(bench_get "$key" 2>/dev/null) || t=""
  if [ -n "$t" ]; then
    mark="${C_D}${t}s${C_N}"
    [ "$(bench_fastest)" = "$key" ] && mark="${C_G}${t}s 本机最快${C_N}"
  else
    mark="${C_R}不可达${C_N}"
  fi
  [ "$cur" = "$key" ] && mark="$mark ${C_C}← 当前${C_N}"
  log "    ${num}) ${name} ${C_D}${url}${C_N}"
  log "         ${mark}"
}

check_connectivity() {
  [ "$NET_CHECKED" = "$EL_MAJOR" ] && return "$NET_RC"
  NET_CHECKED="$EL_MAJOR"
  NET_RC=0

  step "Remi 源检测（官方 / 清华 / 中科大）"
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

# 菜单里的"Remi 源检测"：测完直接给切换选项，不用再去记参数
# 注意只覆盖 remi 的三个源；EPEL / 官方源各有独立入口（菜单 7 / 8），
# 那两个进去是当场实测候选源，和这里的连通性探测不是一回事。
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

  # 换了源必须让 dnf 重新拉元数据，否则它还拿着旧 baseurl 的结果。
  #
  # 关键教训：**不要用 `dnf clean metadata`**。它不理会 --disablerepo/--enablerepo
  # 的作用域，会去遍历所有仓库；metalink 形态的（epel / epel-next / centos.repo）
  # 还要先把 metalink 解析一遍才知道缓存在哪 —— 实测这一步就花掉 41s，
  # 而它做的只是清本地文件，本来不该联网。
  #
  # 正确做法是 `makecache --refresh`：同样强制重拉，但**只碰作用域内的仓库**。
  REPO_READY=""; META_READY=""; CAND_SUFFIX=""; CAND_VALUE=""; NET_CHECKED=""
  build_repo_args 2>/dev/null || true

  if [ ${#PROBE_ARGS[@]} -gt 0 ]; then
    PROBE_LABEL="重新拉取 remi 元数据"
    run_probe "$PROBE_LIMIT" "$PM" "${RO_OPTS[@]}" -q "${PROBE_ARGS[@]}" makecache --refresh >/dev/null \
      && ok "元数据就绪（用时 ${PROBE_ELAPSED}s）" \
      || warn "makecache 未完成，可稍后手动: $PM makecache --refresh"
  else
    # 没识别出 remi 仓库，退回通用作用域（仍只刷 PHP 需要的仓库，不是全量）
    if build_scope_args; then
      local -a s=("${SCOPE_ARGS[@]}")
      PROBE_LABEL="刷新元数据（remi 未识别，按通用作用域）"
      run_probe "$PROBE_LIMIT" "$PM" "${RO_OPTS[@]}" -q makecache --refresh "${s[@]}" >/dev/null \
        && ok "元数据就绪（用时 ${PROBE_ELAPSED}s）" || warn "makecache 未完成"
    else
      warn "拿不到仓库列表，只能全量刷新（会比较慢）"
      PROBE_LABEL="全量刷新元数据"
      run_probe "$PROBE_LIMIT" "$PM" -q makecache --refresh >/dev/null \
        && ok "元数据就绪" || warn "makecache 未完成"
    fi
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
    aliyun) printf '阿里云（mirrors.aliyun.com/epel）' ;;
    huawei) printf '华为云（mirrors.huaweicloud.com/epel）' ;;
    official) printf '官方 metalink（mirrors.fedoraproject.org，由 dnf 自选节点）' ;;
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
#
# 重要：只统计 baseurl，不把 metalink/mirrorlist 混进来。原因是实测踩过的：
#   CentOS-Stream-BaseOS.repo  baseurl=http://mirrors.tencentyun.com/...   ← 真正生效
#   centos.repo                 metalink=https://mirrors.centos.org/...    ← 重复定义但同 id
# 两个文件都定义了 [baseos]，dnf 只会用其中一个；把 metalink 也算进来会
# 得出 "custom:mirrors.centos.org" 这种误导性结论。
detect_host() {
  local files="$1" h
  # 只统计**生效的** baseurl —— 不能把 enabled=0 的也算进来。
  # 实测踩过：CentOS-Stream-Sources.repo 里 7 条 baseurl 都指向 vault.centos.org
  # （全是 Source 段、enabled=0），按"出现次数最多"算就把真正生效的 USTC 盖掉了，
  # 菜单顶部一直显示"自定义（vault.centos.org）"。
  h=$(awk '
        # 关键：baseurl 常写在 enabled 之前（实测 CentOS-Stream-Sources.repo 就是
        # baseurl 在第 5 行、enabled=0 在第 7 行），所以不能边读边判 ——
        # 必须把整个 section 缓冲下来，段末才知道最终 enabled 值再决定要不要统计。
        function flush() {
          if (en == "1" && bu != "") print bu
          bu=""
        }
        /^[[:space:]]*\[/ { flush(); en="1"; bu=""; next }
        /^[[:space:]]*enabled[[:space:]]*=/ {
          v=$0; sub(/^[^=]*=[[:space:]]*/,"",v); gsub(/[[:space:]]+$/,"",v)
          en=v; next
        }
        /^[[:space:]]*baseurl[[:space:]]*=/ {
          line=$0; sub(/^[^=]*=[[:space:]]*/,"",line)
          if (line ~ /^https?:\/\//) bu=line
        }
        END { flush() }
      ' $files 2>/dev/null \
        | grep -viE 'download\.example|localhost|file://' \
        | sed -E 's#^https?://([^/]+).*#\1#' \
        | grep -v '^$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  if [ -z "$h" ]; then
    # 全是 metalink/mirrorlist 形态，退而求其次看这两个（同样只看 enabled）
    h=$(awk '
          function flush() {
            if (en == "1" && ml != "") print ml
            ml=""
          }
          /^[[:space:]]*\[/ { flush(); en="1"; ml=""; next }
          /^[[:space:]]*enabled[[:space:]]*=/ {
            v=$0; sub(/^[^=]*=[[:space:]]*/,"",v); gsub(/[[:space:]]+$/,"",v)
            en=v; next
          }
          /^[[:space:]]*(metalink|mirrorlist)[[:space:]]*=/ {
            line=$0; sub(/^[^=]*=[[:space:]]*/,"",line)
            if (line ~ /^https?:\/\//) ml=line
          }
          END { flush() }
        ' $files 2>/dev/null \
        | grep -viE 'download\.example|localhost' \
        | sed -E 's#^https?://([^/?]+).*#\1#' \
        | grep -v '^$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  fi
  [ -n "$h" ] || { printf 'unknown'; return 0; }
  case "$h" in
    mirrors.fedoraproject.org)   printf 'official' ;;
    mirrors.centos.org)          printf 'official' ;;
    mirrorlist.centos.org)       printf 'official' ;;
    mirror.centos.org)           printf 'official' ;;
    mirrors.tuna.tsinghua.edu.cn) printf 'tuna' ;;
    mirrors.ustc.edu.cn)         printf 'ustc' ;;
    mirrors.aliyun.com)          printf 'aliyun' ;;
    mirrors.huaweicloud.com)     printf 'huawei' ;;
    mirrors.tencentyun.com)      printf 'tencent' ;;
    mirrors.cloud.tencent.com)   printf 'tencent' ;;
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

  # 只处理官方源本体：baseos / appstream / crb。
  # （Sources/Debuginfo/PowerTools 默认 enabled=0，改了也没意义，还会写坏 $basearch 变量）
  #
  # 两种形态都要覆盖，实测两种同时存在且定义了相同的 [section]：
  #   CentOS-Stream-BaseOS.repo  baseurl=http://mirrors.tencentyun.com/$contentdir/...
  #   centos.repo                 metalink=https://mirrors.centos.org/metalink?repo=centos-baseos-...
  # 只改其中一边的话，"listed more than once" 依旧存在，所以两边都收。
  files=$(grep -lE '^[[:space:]]*(baseurl|metalink|mirrorlist)[[:space:]]*=' \
            /etc/yum.repos.d/centos*.repo /etc/yum.repos.d/CentOS*.repo 2>/dev/null \
          | grep -vE 'Sources|Debuginfo|PowerTools|Media|HighAvailability|RealTime|ResilientStorage')
  [ -n "$files" ] || die "没找到 CentOS 官方源 repo 文件（/etc/yum.repos.d/centos*.repo）"

  probe_url "$desc" "${base}/BaseOS/x86_64/os/repodata/repomd.xml" \
    || die "$desc 不可达，先解决网络再切换"

  BACKUP_DIR="$BACKUP_ROOT/os-repo-$TS"
  mkdir -p "$BACKUP_DIR"
  cp -a /etc/yum.repos.d/*.repo "$BACKUP_DIR"/ 2>/dev/null || true
  ok "原配置已备份到 $BACKUP_DIR"

  for f in $files; do
    local fchanged=0

    # ── 形态 A：已有 baseurl（如 CentOS-Stream-BaseOS.repo）
    # 只换 scheme+host，路径里的 $contentdir / $stream / $basearch 全部原样保留。
    # 千万别把路径也拼上 centos-stream/9-stream —— $contentdir 本身就是
    # "centos-stream/9-stream"，拼上去会变成
    #   .../centos-stream/9-stream/$contentdir/$stream/BaseOS/...  → 404
    if grep -qE '^[[:space:]]*baseurl[[:space:]]*=' "$f"; then
      sed -i -E \
        -e 's|^([[:space:]]*)#([[:space:]]*baseurl[[:space:]]*=)|\1\2|' \
        -e "s|^([[:space:]]*baseurl[[:space:]]*=)[[:space:]]*https?://[^/[:space:]]+/|\1https://${SYS_OS_HOST}/|" \
        "$f"
      fchanged=1
      # baseurl 已生效，才注释 mirrorlist（避免两条源并存）
      sed -i -E 's|^([[:space:]]*)mirrorlist[[:space:]]*=|\1#mirrorlist=|' "$f"
      # 再按 section 校正路径：只换 host 修不好上次写错的路径
      repair_os_paths "$f" && fchanged=1
    fi

    # ── 形态 B：只有 metalink/mirrorlist（如 centos.repo）
    # 注释掉 metalink，并按 section 语义写入对应 baseurl。
    # 不这么做的后果：centos.repo 和 CentOS-Stream-*.repo 继续重复定义
    # [baseos]，dnf 每次都刷 "Repository baseos is listed more than once"。
    if grep -qE '^[[:space:]]*(metalink|mirrorlist)[[:space:]]*=' "$f"; then
      local had_ml=0
      grep -qE '^[[:space:]]*metalink[[:space:]]*=' "$f" && had_ml=1
      # 先从 metalink 的 repo= 参数推断 section 用途，写出正确的路径
      local tmp="$f.phpup.$$" sec="" sub="" line
      : > "$tmp"
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
          \#*) printf '%s\n' "$line" >> "$tmp"; continue ;;
        esac
        case "$line" in
          \[*)
            sec=$(printf '%s' "$line" | tr -d '[:space:]')
            printf '%s\n' "$line" >> "$tmp"
            continue ;;
        esac
        # 记录 metalink 里 repo=centos-<name>-$stream 的中间段，用来还原目录名
        if printf '%s' "$line" | grep -qE '^[[:space:]]*(metalink|mirrorlist)[[:space:]]*='; then
          # 从 repo=centos-<name>-$stream 里取 <name>。
          # 两个坑：
          #  1) 别用 sed 贪婪匹配 '.*repo=([a-z]+)-...'，它只会吃到 "centos" 就停；
          #  2) grep -oE 'repo=centos-[a-z]+' 对 "centos-baseos-debug" 只匹配到
          #     "centos-baseos"，会漏掉 -debug/-source 后缀，导致 debug 段被当成
          #     baseos 处理、写进 BaseOS 的 baseurl —— 那是错的（source 段会拉到二进制包）。
          # 所以先看有没有 -debug/-source 后缀，有就不碰这个 section。
          case "$line" in
            *repo=centos-*-debug-*|*repo=centos-*-source-*)
              # enabled=0 的调试/源码段：原样保留 metalink，不动
              printf '%s\n' "$line" >> "$tmp"
              continue ;;
          esac
          # 取 repo=centos-<段>-$stream 的完整 <段>。必须能拿到含连字符的名字：
          # `centos-extras-sig-extras-common-$stream` 的 <段> 是 `extras-sig-extras-common`，
          # 用 grep -oE 'repo=centos-[a-z]+' 只会吃到 "extras" 就停，
          # 于是拼出 .../extras/x86_64/os/ —— 那条 404（实测四个镜像全 404）。
          sub=$(printf '%s' "$line" | sed -nE 's/.*repo=centos-(.*)-[$]stream.*/\1/p')
          case "$sub" in
            baseos|appstream|crb|highavailability|nfv|rt|resilientstorage|extras-common|extras-sig-extras-common)
              printf '#%s\n' "$line" >> "$tmp"
              printf 'baseurl=https://%s/centos-stream/%s\n' "$SYS_OS_HOST" \
                "$(os_repo_path "$sub")" >> "$tmp"
              fchanged=1 ;;
            *)
              # debug / source / debuginfo：enabled=0，原样保留 metalink，不碰。
              printf '%s\n' "$line" >> "$tmp" ;;
          esac
          sub=""
          continue
        fi
        printf '%s\n' "$line" >> "$tmp"
      done < "$f"
      mv "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; die "写入 $f 失败"; }
      [ "$had_ml" = 1 ] || true
    fi

    if [ "$fchanged" = 0 ]; then
      warn "$(basename "$f") 没有可改的 baseurl/metalalink，跳过（未改动）"
      continue
    fi

    # 安全网：处理完必须还有生效的源，且必须指向目标镜像
    if ! grep -qE '^[[:space:]]*(baseurl|metalink|mirrorlist)[[:space:]]*=' "$f"; then
      cp -a "$BACKUP_DIR/$(basename "$f")" "$f"
      bad "$(basename "$f") 改写后没有任何生效源，已从备份还原"
      die "仓库配置未改动"
    fi
    if ! grep -qE "^[[:space:]]*baseurl[[:space:]]*=[[:space:]]*https://${SYS_OS_HOST}/" "$f"; then
      cp -a "$BACKUP_DIR/$(basename "$f")" "$f"
      bad "$(basename "$f") 的 baseurl 没换成 $SYS_OS_HOST ，已从备份还原，仓库配置未改动"
      warn "它原本长这样（发我我按实际格式调）："
      grep -E '^[[:space:]]*#?[[:space:]]*(baseurl|metalink)[[:space:]]*=' "$BACKUP_DIR/$(basename "$f")" | sed 's/^/      /'
      die "这是地址格式没匹配上，不是网络问题"
    fi

    ok "已更新 $(basename "$f")"
    grep -E '^[[:space:]]*baseurl[[:space:]]*=' "$f" | sed 's|^[[:space:]]*|      |'
  done

  refresh_sys_meta
  return 0
}

# 换完系统源后刷新缓存。只刷这些源，不要全量。
#
# 关键：makecache 必须加仓库作用域（--disablerepo + --enablerepo），
# 否则 dnf 会把全部 enabled 仓库的元数据都拉一遍。除了刚换的 baseos/appstream/crb，
# 还有 Aeris(~6 kB/s)、ELRepo、epel-next、腾讯云源… 每次换源都白等一两分钟。
#
# 另外同样不能用 `dnf clean metadata` 打头（见 apply_mirror 里的说明）：
# 它不看作用域，会去解析所有 metalink 仓库，实测白等 41s。用 --refresh 代替。
# 这跟上面 refresh_meta 处理 remi 的做法是同一个道理。
refresh_sys_meta() {
  REPO_READY=""; META_READY=""; CAND_SUFFIX=""; CAND_VALUE=""
  [ ${#RO_OPTS[@]} -gt 0 ] || return 0

  local -a scope
  build_scope_args || {
    warn "拿不到仓库列表（repolist 超时），跳过元数据刷新，避免盲等"
    return 0
  }
  scope=("${SCOPE_ARGS[@]}")

  PROBE_LABEL="重新拉取系统源元数据"
  # 别把 stderr 丢掉 —— 之前失败只说"makecache 未完成（4s）"，
  # 用户根本看不出是 URL 404、仓库名不认还是网络问题（实测反馈）。
  # 几秒就失败是配置错误不是网络慢，必须把原因打出来。
  local mc_rc=0
  run_probe "$PROBE_LIMIT" "$PM" "${RO_OPTS[@]}" -q makecache --refresh "${scope[@]}" >/dev/null || mc_rc=$?
  if [ "$mc_rc" -eq 0 ]; then
    ok "元数据就绪（用时 ${PROBE_ELAPSED}s，只刷新 PHP 需要的仓库）"
  else
    warn "makecache 未完成（${PROBE_ELAPSED}s，rc=$mc_rc）"
    if [ "$PROBE_ELAPSED" -lt 5 ]; then
      warn "${C_Y}几秒就失败 = 配置问题（不是网络慢）${C_N}，常见原因："
      warn "  1) 某个 baseurl 404（换源时路径拼错）→ 用菜单 5 重新换一次源"
      warn "  2) 仓库 id 不被 dnf 认可（下面若出现 No repository match）"
      warn "  3) repo 文件被改坏 → 从 $BACKUP_ROOT 恢复"
    else
      warn "链路太慢，可稍后手动: $PM makecache --refresh"
    fi
    if [ -n "$PROBE_ERR" ]; then
      log "  ${C_D}--- dnf 报错（前 12 行）---${C_N}"
      printf '%s\n' "$PROBE_ERR" | sed 's/^/    /' | head -12
      log "  ${C_D}---${C_N}"
    fi
  fi
  PROBE_LABEL=""
  return 0
}

# CentOS Stream 9 各仓库在镜像站上的**真实**目录结构。
# 实测踩过的坑：extras-common 不在 9-stream/ 下，而在 SIGs/ 下，且结尾不是 /os/：
#   正常仓库  .../centos-stream/9-stream/CRB/x86_64/os/
#   SIGs 仓库 .../centos-stream/SIGs/9-stream/extras/x86_64/extras-common/
# 拼错就 404，dnf 的 makecache 会秒失败。
os_repo_path() {
  local a="${BASEARCH:-x86_64}"
  case "$1" in
    baseos)               printf '%s-stream/BaseOS/%s/os/'           "${EL_MAJOR}" "$a" ;;
    appstream)            printf '%s-stream/AppStream/%s/os/'        "${EL_MAJOR}" "$a" ;;
    crb)                  printf '%s-stream/CRB/%s/os/'              "${EL_MAJOR}" "$a" ;;
    highavailability)     printf '%s-stream/HighAvailability/%s/os/' "${EL_MAJOR}" "$a" ;;
    nfv)                  printf '%s-stream/NFV/%s/os/'              "${EL_MAJOR}" "$a" ;;
    rt)                   printf '%s-stream/RT/%s/os/'               "${EL_MAJOR}" "$a" ;;
    resilientstorage)     printf '%s-stream/ResilientStorage/%s/os/' "${EL_MAJOR}" "$a" ;;
    # 注意两个名字指同一个仓库：section 名是 extras-common，
    # 而 metalink 里的段名是 extras-sig-extras-common。
    # 只认一个就会漏（实测：repair 静默不修，坏路径一直留着）。
    extras-common|extras-sig-extras-common)
      printf 'SIGs/%s-stream/extras/%s/extras-common/' "${EL_MAJOR}" "$a" ;;
    *) return 1 ;;
  esac
}

# 按 section 校正 baseurl 路径。
#
# 为什么必须有这一步：baseurl 形态的换源只换 host、不换路径（因为路径里可能有
# $contentdir/$stream 这类 dnf 变量）。如果上次换源把路径拼错了（实测 extras-common
# 被拼成 .../9-stream/extras/x86_64/os/，四个镜像全 404），坏路径会一直留在文件里，
# 再换一次源也修不好 —— 因为只换了 host。这里按 section 重写成规范路径。
#
# 只处理 os_repo_path 认识的 section；debug/source 等不认识的原样保留。
repair_os_paths() {   # $1=file；有改动返回 0
  local f=$1 tmp="$1.phpup.$$" sec="" line p changed=0
  : > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      \[*)
        sec=$(printf '%s' "$line" | tr -d '[:space:]')
        sec=${sec#\[}; sec=${sec%\]} ;;
    esac
    if [ -n "$sec" ] && p=$(os_repo_path "$sec"); then
      if printf '%s' "$line" | grep -qE '^[[:space:]]*baseurl[[:space:]]*='; then
        printf 'baseurl=https://%s/centos-stream/%s\n' "$SYS_OS_HOST" "$p" >> "$tmp"
        changed=1
        continue
      fi
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$f"
  if [ "$changed" = 1 ]; then
    mv "$tmp" "$f"
    return 0
  fi
  rm -f "$tmp"
  return 1
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

# 收集 (section, 文件, enabled) 三元组，供去重逻辑用。
# 为什么要带 enabled：同一个 [baseos] 可能一份 enabled=1、一份 enabled=0，
# 必须保留 enabled=1 的那份，否则去重等于把仓库关掉了。
collect_repo_sections() {
  local f
  for f in /etc/yum.repos.d/*.repo; do
    [ -f "$f" ] || continue
    awk -v F="$f" '
      function emit() { if (cur != "") print cur "\t" F "\t" en }
      /^[[:space:]]*\[/ {
        emit()
        n=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", n)
        gsub(/^\[/, "", n); gsub(/\]$/, "", n)
        cur=n; en="1"
        next
      }
      /^[[:space:]]*enabled[[:space:]]*=/ {
        v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v)
        en=v
      }
      END { emit() }
    ' "$f"
  done 2>/dev/null
}

# 把某个文件里指定 section 的整段注释掉（段头 + 段内所有行）。
comment_out_section() {   # $1=file $2=section
  local f=$1 sec=$2 tmp="$1.phpup.$$"
  awk -v sec="$sec" '
    BEGIN { inb=0 }
    /^[[:space:]]*\[/ {
      n=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", n)
      gsub(/^\[/, "", n); gsub(/\]$/, "", n)
      if (inb) inb=0
      if (n == sec) { inb=1; print "#" $0; next }
    }
    { if (inb) print "#" $0; else print $0 }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# ── 自动去重 ─────────────────────────────────────────────────────────
# 同名 [section] 被多个文件定义时，dnf 只认解析到的那一个，另一个白白污染
# 输出（"listed more than once"）。这里自动把多余的那份整段注释掉。
#
# 为什么是"注释"而不是"删文件"：
#   · 一个文件里往往既有重复 section 也有独有 section，整文件 mv 会误伤
#   · 注释可逆，配合备份可随时还原
#
# 保留规则（确定性、可解释）：
#   1) 优先在 enabled=1 的定义里挑 —— 否则等于把仓库关掉
#   2) 若全部 enabled=0，照样要去重：dnf 的 "listed more than once"
#      是在**解析配置**时报的，跟 enabled 无关，留着警告就不会消失
#   3) 文件名包含 section 名的优先（baseos -> CentOS-Stream-BaseOS.repo）
#   4) 都不符合就保留字典序第一个，与 dnf 的解析顺序一致
fix_duplicate_repos() {
  local pairs dup_total=0 fixed=0 skipped=0
  pairs=$(collect_repo_sections)
  [ -n "$pairs" ] || return 1

  # 只挑出"同一 section 出现多次"的组
  local dups
  dups=$(printf '%s\n' "$pairs" | awk -F'\t' '
    { cnt[$1]++; rows[$1]=rows[$1] $0 "\n" }
    END { for (s in cnt) if (cnt[s] > 1) printf "%s", rows[s] }
  ')
  [ -n "$dups" ] || return 1

  BACKUP_DIR="$BACKUP_ROOT/dup-repo-$TS"
  mkdir -p "$BACKUP_DIR"

  # 逐个 section 决定谁留下
  local sections s
  sections=$(printf '%s\n' "$dups" | awk -F'\t' '{print $1}' | sort -u)
  for s in $sections; do
    dup_total=$((dup_total + 1))
    local group keeper="" loser_list=""
    group=$(printf '%s\n' "$dups" | awk -F'\t' -v want="$s" '$1==want')

    # 1) 优先在 enabled=1 的里挑；全 enabled=0 就退回整组（仍要消警告）
    local pool
    pool=$(printf '%s\n' "$group" | awk -F'\t' '$3=="1"')
    [ -n "$pool" ] || pool="$group"

    # 2) 文件名包含 section 名的优先
    local row f
    while IFS=$(printf '\t') read -r _ f _; do
      [ -n "$f" ] || continue
      local base; base=$(basename "$f" .repo | tr '[:upper:]' '[:lower:]')
      if [ -z "$keeper" ] && printf '%s' "$base" | grep -qF "$s"; then
        keeper="$f"
      fi
    done <<EOF
$pool
EOF

    # 3) 兜底：字典序第一个
    if [ -z "$keeper" ]; then
      keeper=$(printf '%s\n' "$pool" | awk -F'\t' '{print $2}' | sort | head -1)
    fi

    while IFS=$(printf '\t') read -r _ f _; do
      [ -n "$f" ] || continue
      [ "$f" = "$keeper" ] && continue
      loser_list="$loser_list $f"
    done <<EOF
$pool
EOF

    [ -n "$loser_list" ] || continue

    # 备份涉及的文件（只备份一次）
    for f in $keeper $loser_list; do
      [ -f "$BACKUP_DIR/$(basename "$f")" ] || cp -a "$f" "$BACKUP_DIR/" 2>/dev/null || true
    done

    for f in $loser_list; do
      comment_out_section "$f" "$s"
      # 安全网：注释后该 section 在这个文件里必须没有生效的源了
      if awk -v sec="$s" '
        BEGIN{inb=0; bad=0}
        /^[[:space:]]*\[/ {
          n=$0; gsub(/^[[:space:]]+|[[:space:]]+$/,"",n); gsub(/^\[/,"",n); gsub(/\]$/,"",n)
          if (inb) inb=0
          if (n==sec) inb=1
        }
        inb && /^[[:space:]]*(baseurl|metalink|mirrorlist)[[:space:]]*=/ { bad=1 }
        END{exit bad}
      ' "$f"; then
        fixed=$((fixed + 1))
        ok "[$s] 保留 $(basename "$keeper")，已注释 $(basename "$f")"
      else
        cp -a "$BACKUP_DIR/$(basename "$f")" "$f" 2>/dev/null || true
        bad "[$s] 注释 $(basename "$f") 后仍有生效源，已从备份还原"
        skipped=$((skipped + 1))
      fi
    done
  done

  log ""
  if [ "$fixed" -gt 0 ]; then
    ok "去重完成：处理 $fixed 处重复定义${skipped:+（跳过 $skipped 处）}"
    log "  ${C_D}备份在 $BACKUP_DIR，还原: cp -a $BACKUP_DIR/*.repo /etc/yum.repos.d/${C_N}"
  else
    info "没有需要处理的重复定义"
  fi
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
  #
  # repolist 的输出格式是 "repo id  repo name  status" 三列，第一行是表头。
  # 之前用 `awk 'NR>1 {print $1}'` 只跳 1 行，若 dnf 额外打了
  # "Last metadata expiration check..." 这类行，表头就会被当成 repo id 抓进来，
  # 而真正的 baseos/appstream 反而被挤掉 —— 结果"所有仓库 < 1s"的结论建立在
  # 不完整的数据上。改成按内容过滤：只保留出现在 repo 文件里的 id。
  local ids all_ids id
  all_ids=$(timeout 30 "$PM" "${RO_OPTS[@]}" repolist --enabled 2>/dev/null \
              | awk 'NF>=2 && $1 ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { print $1 }' | sort -u)
  if [ -z "$all_ids" ]; then
    warn "拿不到仓库列表（repolist 超时）"
    return 0
  fi

  # 只测在 repo 文件里真实存在的 section，把表头/杂行挡在外面
  ids=""
  for id in $all_ids; do
    grep -lqE "^[[:space:]]*\[${id}\][[:space:]]*$" /etc/yum.repos.d/*.repo 2>/dev/null && ids="$ids $id"
  done
  ids=${ids# }
  if [ -z "$ids" ]; then
    warn "repolist 返回的 id 都没在 repo 文件里找到对应 section，无法测速"
    return 0
  fi

  local total skipped=0 probed=0
  total=$(printf '%s\n' $ids | grep -c .)
  info "逐个探测 repomd.xml 响应时间（超过 1s 就会明显拖慢 dnf）"
  log "  ${C_D}共 $total 个 enabled 仓库${C_N}"
  log ""
  local slow="" url kind

  # 取某个 repo id 的源地址。两种形态都要处理：
  #   baseurl=  → 直接拼 repomd.xml
  #   metalink= → 先解析 metalink 拿真实 mirror 列表，再取其中一个测速。
  #               之前只认baseurl，导致 EPEL（默认 metalink）直接被 continue 跳过，
  #               体检报告里永远看不到它 —— 而它恰恰是最慢的那个。
  for id in $ids; do
    url=""
    kind=""

    # baseurl 形态：多个文件可能重复定义同名 section，只取第一个生效的。
    # 段头匹配要容忍尾随空格/制表符（真实文件里 [baseos] 后面常带空白）。
    url=$(awk -v want="$id" '
      {
        h=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", h)
        if (h == "[" want "]") { inb=1; next }
        if (h ~ /^\[/) inb=0
      }
      inb && /^[[:space:]]*baseurl[[:space:]]*=/ {
        sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
    ' /etc/yum.repos.d/*.repo 2>/dev/null | head -1)

    if [ -n "$url" ]; then
      kind="baseurl"
      url="${url%/}/repodata/repomd.xml"
    else
      # metalink 形态：metalink 本身不是仓库地址，得先解析它
      local ml
      ml=$(awk -v want="$id" '
        {
          h=$0
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", h)
          if (h == "[" want "]") { inb=1; next }
          if (h ~ /^\[/) inb=0
        }
        inb && /^[[:space:]]*metalink[[:space:]]*=/ {
          sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
      ' /etc/yum.repos.d/*.repo 2>/dev/null | head -1)

      if [ -n "$ml" ]; then
        kind="metalink"
        # metalink 的真实结构（Fedora mirrors，metalink 3.0）：
        #   <url protocol="https" type="https" location="US" preference="40">https://.../repomd.xml</url>
        # 地址是**元素文本**，不是 href 属性 —— 只有老式 mirrorlist 才用 href。
        # 这里抓 https 的最高 preference 那条（dnf 也是这么挑的）。
        url=$(curl -fsS --connect-timeout 3 --max-time 8 \
                "$(printf '%s' "$ml" | sed -e "s/\$basearch/$(rpm -E '%{_arch}' 2>/dev/null || echo x86_64)/g" \
                                                      -e "s/\$releasever/${EL_MAJOR}/g" \
                                                      -e "s/\$infra/x86_64/g" -e "s/\$contentdir/centos-stream/g")" \
              2>/dev/null \
              | grep -oE '<url protocol="https"[^>]*>[^<]+</url>' \
              | head -1 | sed -E 's/.*>([^<]+)<.*/\1/')
        [ -n "$url" ] && url="${url%/}"
      fi
    fi

    if [ -z "$url" ]; then
      skipped=$((skipped + 1))
      log "  ${C_Y}?${C_N} $id   ${C_D}拿不到源地址（没有生效的 baseurl/metalink），跳过${C_N}"
      continue
    fi
    # 把 dnf 变量展开（metalink 分支里部分变量已在上面展开过，这里兜底）
    url=$(printf '%s' "$url" | sed -e "s/\$basearch/$(rpm -E '%{_arch}' 2>/dev/null || echo x86_64)/g" \
                             -e "s/\$releasever/${EL_MAJOR}/g" -e "s/\$stream/${EL_MAJOR}-stream/g" \
                             -e "s|\$contentdir|centos-stream/${EL_MAJOR}-stream|g")
    case "$url" in http://*|https://*) ;; *)
      skipped=$((skipped + 1))
      log "  ${C_Y}?${C_N} $id   ${C_D}源地址不是 http(s)，跳过${C_N}"
      continue ;;
    esac

    if probe_url "$id" "$url" >/dev/null 2>&1; then
      probed=$((probed + 1))
      if [ -n "$PROBE_LAST_T" ] && awk "BEGIN{exit !($PROBE_LAST_T > 1.0)}" 2>/dev/null; then
        log "  ${C_Y}⚠${C_N} $id   ${PROBE_LAST_T}s  ${C_D}偏慢（$kind）${C_N}"
        slow="$slow $id"
      else
        log "  ${C_G}✓${C_N} $id   ${PROBE_LAST_T}s  ${C_D}$kind${C_N}"
      fi
    else
      skipped=$((skipped + 1))
    fi
  done

  log ""
  info "覆盖情况：实测 $probed 个 / 共 $total 个 enabled 仓库${skipped:+（跳过 $skipped 个）}"
  if [ -n "$slow" ]; then
    warn "这些源响应 >1s，dnf 会在这里耗掉大部分时间：$slow"
    log "  ${C_D}上面每个仓库的耗时都是本机实测，不是估计值${C_N}"
    log "  ${C_D}换 EPEL: 菜单 7；换官方源: 菜单 8（进入后会再实测一遍候选源）${C_N}"
  elif [ "$probed" -eq "$total" ]; then
    ok "所有仓库响应都 < 1s，元数据加载不会成为瓶颈"
  else
    # 有仓库没测到就不下"全都不慢"的结论 —— 那是拿不完整数据骗人
    warn "已测到的 $probed 个都 < 1s，但还有 $skipped 个没测到，不足以判断整体不慢"
    log "  ${C_D}没测到的通常是缺 baseurl/metalink 或解析失败，建议手工确认它们是否需要${C_N}"
  fi

  # 重复定义：直接自动处理，不再让人手动 mv
  local dups
  if dups=$(find_duplicate_repos); then
    log ""
    warn "以下 repo id 被多个文件重复定义（dnf 会刷 'listed more than once'）:"
    printf '%s\n' "$dups"
    log ""
    info "自动去重：保留一份、把其余整段注释掉（会先备份到 $BACKUP_ROOT/dup-repo-$TS）"
    fix_duplicate_repos
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
  local cur stream choice ver epelm osm
  cur=$(current_php_version)
  stream=$(enabled_php_stream)
  epelm=$(current_epel_mirror)
  osm=$(current_os_mirror)

  log ""
  log "=================================================================="
  log " ${C_B}PHP 升级工具${C_N}   $PRETTY_OS · $PM"
  log "------------------------------------------------------------------"
  log " 当前 ${cur:-未安装}   module ${stream:-<未启用>}   目标 ${C_B}PHP $TARGET${C_N}"
  log " ${C_B}Remi 源${C_N}  : $(mirror_label "$(current_remi_mirror)")"
  log " ${C_B}EPEL 源${C_N}  : $(sys_epel_label "$epelm")"
  log " ${C_B}官方源${C_N}   : $(sys_os_label "$osm")"
  log "=================================================================="
  log "  ${C_B}升级${C_N}"
  log "  1) 执行升级         升到仓库最新（可换版本）"
  log "  2) 预演升级         只看会改什么，不落地"
  log "  3) 安全补丁         只升 patch，不动分支"
  log ""
  log "  ${C_B}源管理${C_N}"
  log "  4) 切换源           Remi / EPEL / 官方，进入即实测"
  log ""
  log "  ${C_B}其他${C_N}"
  log "  5) 当前状态"
  log "  6) 参数说明"
  log "  0) 退出"
  log ""

  while :; do
    drain_input
    printf "请选择 [0-6]: "
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
      4) pick_source_kind || continue; return 0 ;;
      5) MODE="status"; log ""; return 0 ;;
      6) log ""; usage; log "" ;;
      0|q|Q) log "已退出"; exit 0 ;;
      *) bad "请输入 0-6" ;;
    esac
  done
}


# 切换源的二级菜单：三个源统一入口，进去各自会当场实测候选镜像。
pick_source_kind() {
  local c
  log ""
  log "  ${C_B}源管理${C_N}"
  log "  1) 切换 Remi     当前 $(mirror_label "$(current_remi_mirror)")"
  log "  2) 切换 EPEL     当前 $(sys_epel_label "$(current_epel_mirror)")"
  log "  3) 切换官方源   当前 $(sys_os_label "$(current_os_mirror)")"
  log "  4) 全面体检     逐个测速 + 查重复定义"
  log "  0) 返回"
  drain_input
  printf "请选择 [0-4]: "
  read -r c || return 1
  case "$c" in
    1) MODE="mirror";      log ""; return 0 ;;
    2) MODE="mirror-epel"; log ""; return 0 ;;
    3) MODE="mirror-os";   log ""; return 0 ;;
    4) MODE="audit";       log ""; return 0 ;;
    *) log "  已返回"; return 1 ;;
  esac
}

# ── 各源现场测速展示（检测菜单和切换菜单共用）────────────────────────
# 三处调用同一套 bench_*，保证"检测看到的数字"和"切换时看到的"完全一致。
show_remi_bench() {
  BENCH_KEYS=(); BENCH_TIMES=()
  bench_one official "https://rpms.remirepo.net/enterprise/${EL_MAJOR}/safe/x86_64/repodata/repomd.xml"
  bench_one tuna     "https://mirrors.tuna.tsinghua.edu.cn/remi/enterprise/${EL_MAJOR}/safe/x86_64/repodata/repomd.xml"
  bench_one ustc     "https://mirrors.ustc.edu.cn/remi/enterprise/${EL_MAJOR}/safe/x86_64/repodata/repomd.xml"
  log "  ${C_B}Remi 源（本机实测）${C_N}"
  bench_menu_line 1 "官方   " official "rpms.remirepo.net" "$(current_remi_mirror)"
  bench_menu_line 2 "清华   " tuna     "mirrors.tuna.tsinghua.edu.cn" "$(current_remi_mirror)"
  bench_menu_line 3 "中科大 " ustc     "mirrors.ustc.edu.cn" "$(current_remi_mirror)"
}

show_epel_bench() {
  BENCH_KEYS=(); BENCH_TIMES=()
  bench_one official "https://mirrors.fedoraproject.org/metalink?repo=epel-${EL_MAJOR}&arch=x86_64"
  bench_one tuna     "https://mirrors.tuna.tsinghua.edu.cn/epel/${EL_MAJOR}/Everything/x86_64/repodata/repomd.xml"
  bench_one ustc     "https://mirrors.ustc.edu.cn/epel/${EL_MAJOR}/Everything/x86_64/repodata/repomd.xml"
  bench_one aliyun   "https://mirrors.aliyun.com/epel/${EL_MAJOR}/Everything/x86_64/repodata/repomd.xml"
  bench_one huawei   "https://mirrors.huaweicloud.com/epel/${EL_MAJOR}/Everything/x86_64/repodata/repomd.xml"
  log "  ${C_B}EPEL 源（本机实测）${C_N}"
  bench_menu_line 1 "官方   " official "mirrors.fedoraproject.org/metalink" "$(current_epel_mirror)"
  bench_menu_line 2 "清华   " tuna     "mirrors.tuna.tsinghua.edu.cn/epel" "$(current_epel_mirror)"
  bench_menu_line 3 "中科大 " ustc     "mirrors.ustc.edu.cn/epel" "$(current_epel_mirror)"
  bench_menu_line 4 "阿里云 " aliyun   "mirrors.aliyun.com/epel" "$(current_epel_mirror)"
  bench_menu_line 5 "华为云 " huawei   "mirrors.huaweicloud.com/epel" "$(current_epel_mirror)"
}

show_os_bench() {
  BENCH_KEYS=(); BENCH_TIMES=()
  bench_one tencent  "http://mirrors.tencentyun.com/centos/${EL_MAJOR}-stream/BaseOS/x86_64/os/repodata/repomd.xml"
  bench_one tuna     "https://mirrors.tuna.tsinghua.edu.cn/centos-stream/${EL_MAJOR}-stream/BaseOS/x86_64/os/repodata/repomd.xml"
  bench_one ustc     "https://mirrors.ustc.edu.cn/centos-stream/${EL_MAJOR}-stream/BaseOS/x86_64/os/repodata/repomd.xml"
  bench_one aliyun   "https://mirrors.aliyun.com/centos-stream/${EL_MAJOR}-stream/BaseOS/x86_64/os/repodata/repomd.xml"
  bench_one huawei   "https://mirrors.huaweicloud.com/centos-stream/${EL_MAJOR}-stream/BaseOS/x86_64/os/repodata/repomd.xml"
  bench_one official "https://mirrors.centos.org/metalink?repo=centos-baseos-${EL_MAJOR}-stream&arch=x86_64"
  log "  ${C_B}官方源（本机实测 BaseOS）${C_N}"
  bench_menu_line 1 "腾讯云 " tencent  "mirrors.tencentyun.com" "$(current_os_mirror)"
  bench_menu_line 2 "清华   " tuna     "mirrors.tuna.tsinghua.edu.cn" "$(current_os_mirror)"
  bench_menu_line 3 "中科大 " ustc     "mirrors.ustc.edu.cn" "$(current_os_mirror)"
  bench_menu_line 4 "阿里云 " aliyun   "mirrors.aliyun.com" "$(current_os_mirror)"
  bench_menu_line 5 "华为云 " huawei   "mirrors.huaweicloud.com" "$(current_os_mirror)"
  bench_menu_line 6 "官方   " official "mirrors.centos.org/metalink" "$(current_os_mirror)"
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
  local cand rc
  step "目标分支可得性"
  info "查 php-common 候选版本（只读 remi 仓库，最多 60s；超时则跳过本项检查）"
  cand=$(candidate_php_common)
  log "  稳定仓库最新 php-common: ${cand:-<查询失败或超时>}"

  # RC 单独报，且**只报不装**。用户在 Remi 博客看到的版本号常是 RC，
  # 不说清楚就会以为"官网有 8.5.12 了，这脚本怎么查不到"。
  rc=$(candidate_rc_php_common)
  if [ -n "$rc" ]; then
    log "  ${C_Y}测试仓库 RC${C_N}   : $rc  ${C_D}（Remi 明确标注不适合生产）${C_N}"
  else
    log "  ${C_D}测试仓库 RC   : 无${C_N}"
  fi

  if [ -z "$cand" ]; then
    warn "查不到稳定版候选：网络慢、镜像同步延迟，或 ${REPO_ARGS[*]} 未真正启用"
    warn "这项只是预检，跳过不影响后续；实际升级时 dnf 会自己算依赖并给出结论"
    return 1
  fi

  # 稳定版分支判断（原有逻辑）
  case "$cand" in
    "$TARGET".*) ok "稳定仓库已提供 PHP $TARGET（$cand）" ;;
    *)
      bad "稳定仓库最新为 $cand，不是 $TARGET 分支"
      log "${C_D}  常见原因：remi-release 太旧（不认 php:remi-$TARGET）→ $PM update remi-release -y${C_N}"
      log "${C_D}  或该 el${EL_MAJOR} 版本已不再由 Remi 构建 $TARGET${C_N}"
      return 1
      ;;
  esac

  # 有 RC 就摆出来，并给一个**真实的选择入口** ——
  # 不能只说"由你决定"却没地方选，那等于没实现。
  if [ -n "$rc" ]; then
    log ""
    if [ "$USE_RC" = 1 ]; then
      warn "已指定 --rc：将使用测试仓库的 $rc（RC 版，非生产）"
    elif [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
      # 无人值守 / 非交互：绝不擅自上 RC，只提示怎么开
      info "测试仓库有 $rc（比稳定版新），本次保持稳定版 $cand"
      log "  ${C_D}要上 RC 请显式加 --rc：sudo $PROG --rc ...   （Remi 官方标注不适合生产）${C_N}"
    else
      info "测试仓库有 $rc，比稳定版 $cand 新"
      log "  ${C_D}Remi 官方标注 RC 不适合生产；上生产建议等稳定版${C_N}"
      drain_input
      printf "  是否改用 RC 版本 $rc ？[y/N]: "
      local ans=""
      read -r ans || ans=""
      case "$ans" in
        y|Y|yes|YES)
          USE_RC=1
          warn "已选择 RC：$rc（Remi 标注不适合生产）"
          # 仓库作用域必须重算，否则升级时仍只加载稳定仓库，RC 根本装不上
          REPO_READY=""; META_READY=""; CAND_SUFFIX=""; CAND_VALUE=""
          build_repo_args 2>/dev/null || true
          ok "已把测试仓库纳入本次升级范围"
          ;;
        *)
          info "保持稳定版 $cand（推荐）"
          log "  ${C_D}稳定仓库出 $TARGET 正式包后跑 --security 即可${C_N}"
          ;;
      esac
    fi
  fi
  return 0
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

# 升级 PHP 时真正需要参与解析的仓库。
#   · PHP 包本体和它的大部分依赖在 remi / remi-safe / remi-modular
#   · 系统级依赖（openssl、libxml2、oniguruma 等）在 baseos / appstream
#   · EPEL 只有极少数 php-* 依赖会用到；Aeris / ELRepo 基本与 PHP 无关，
#     但 dnf 默认会把所有 enabled 仓库的元数据全拉一遍 —— 实测 EPEL 官方
#     metalink 只有 11 kB/s，Aeris 6 kB/s，合计能把 upgrade 拖成半小时。
# 所以这里显式列白名单，而不是让 dnf 全量加载。
php_repo_scope() {
  PHP_SCOPE_ARGS=()
  local id avail

  # 只对**真实存在**的仓库下发 --enablerepo/--disablerepo。
  # 不这么做就会在每次升级前刷一屏 "No repository match: remi-php74" 之类的
  # 警告（用户实测贴出来的那 7 行）—— dnf 对不存在的仓库名会抱怨，纯噪音。
  avail=$(timeout "$RO_TIMEOUT" "$PM" "${RO_OPTS[@]}" repolist --all 2>/dev/null \
            | awk 'NR>1 {print $1}' | sort -u)

  for id in baseos appstream crb extras-common remi remi-safe remi-modular epel; do
    [ "$PM" = dnf ] || continue
    printf '%s\n' "$avail" | grep -qx "$id" && PHP_SCOPE_ARGS+=("--enablerepo=$id")
  done

  # 用户显式 --rc 时才把测试仓库纳入升级范围；
  # 反过来，没开 --rc 就**显式关掉**测试仓库 —— php_repo_scope 没有用
  # --disablerepo='*'，未列出的仓库保持其默认状态。万一测试仓库被手动启用过，
  # 不显式关掉，RC 就会漏进生产升级。
  if [ "$USE_RC" = 1 ]; then
    for id in remi-modular-test remi-test; do
      [ "$PM" = dnf ] || continue
      printf '%s\n' "$avail" | grep -qx "$id" && PHP_SCOPE_ARGS+=("--enablerepo=$id")
    done
  else
    for id in remi-modular-test remi-test "remi-php74-test" "remi-php80-test" \
              "remi-php81-test" "remi-php82-test" "remi-php83-test" \
              "remi-php84-test" "remi-php85-test"; do
      [ "$PM" = dnf ] || continue
      printf '%s\n' "$avail" | grep -qx "$id" && PHP_SCOPE_ARGS+=("--disablerepo=$id")
    done
  fi

  # 其余一律关掉。同样只关真实存在的。
  for id in aeris aeris-testing \
            elrepo elrepo-testing elrepo-kernel elrepo-extras \
            epel-next epel-next-testing epel-cisco-openh264 \
            epel-debuginfo epel-source \
            remi-php74 remi-php80 remi-php81 remi-php82 \
            remi-php83 remi-php84 remi-php85; do
    [ "$PM" = dnf ] || continue
    printf '%s\n' "$avail" | grep -qx "$id" && PHP_SCOPE_ARGS+=("--disablerepo=$id")
  done
  return 0
}

upgrade_packages() {
  step "升级 PHP 包（通配 php*，不逐个列包名）"

  php_repo_scope

  if [ "$MODE" != apply ]; then
    log "  预演输出（--assumeno，会中止，不落地）:"
    timeout 300 "$PM" "${PHP_SCOPE_ARGS[@]}" --setopt=timeout=30 --setopt=retries=1 \
      --setopt=minrate=1024 \
      upgrade --assumeno 'php*' 2>&1 | sed 's/^/    /' | head -50
    log ""
    log "${C_D}  重点看 php-common 的版本变化：跨 minor 就是换分支，不是打补丁${C_N}"
    log "${C_D}  已排除 Aeris / ELRepo / epel-next 等与 PHP 无关的仓库以提速${C_N}"
    return 0
  fi

  info "只加载 remi / baseos / appstream / crb / epel，已跳过 Aeris、ELRepo、epel-next"
  local rc=0
  if [ "$PM" = dnf ] && [ -n "$CUR_STREAM" ]; then
    # 实时输出：dnf 自己的进度条能证明它没死，别再拿 tail 把过程吞掉
    "$PM" "${PHP_SCOPE_ARGS[@]}" -y distro-sync 'php*'
    rc=$?
  else
    "$PM" "${PHP_SCOPE_ARGS[@]}" -y update 'php*'
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
#升级前提醒：EPEL 走官方 metalink 是"dnf 卡半小时"的头号原因。
# 不用联网探测（省时间），只看 repo 文件里 EPEL 是不是还指着 metalink。
warn_if_slow_epel() {
  local m
  m=$(current_epel_mirror)
  case "$m" in
    tuna|ustc|aliyun|huawei) return 0 ;;   # 已换国内镜像，不用啰嗦
  esac

  grep -qE '^[[:space:]]*metalink[[:space:]]*=' /etc/yum.repos.d/epel.repo 2>/dev/null || return 0

  # 不要在这里断言"多快算慢""谁最快" —— 那是每台机器自己的事。
  # 只陈述结构性的事实（metalink 要多一跳、由 dnf 自选节点），让用户去菜单 7 看本机实测。
  warn "EPEL 还在用官方 metalink（$(sys_epel_label "$m")）"
  log "  ${C_D}metalink 的含义：把选节点这件事交给 dnf，要多一跳解析 + 它可能选到境外节点${C_N}"
  log "  ${C_D}PHP 升级用不到 EPEL 的包，但 dnf 仍会先拉它的元数据${C_N}"
  log "  ${C_D}想确认慢不慢：菜单 9 系统源体检，或菜单 7 会当场实测各候选源${C_N}"
  log "  ${C_D}已自动跳过与 PHP 无关的仓库（Aeris / ELRepo / epel-next 等）${C_N}"
  log ""
  return 0
}

version_channel() {
  # 升级前后的版本号，函数作用域：确认段和最后的完成提示都要用。
  #（不能在 if 块里 local，否则 -y 模式下确认块不执行，完成提示就取不到。）
  local vcur="" vnew=""
  show_state
  warn_if_slow_epel
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

  # 版本完全一致就不升级：白跑一次事务、还可能把服务动一遍，线上尤其不能这么干。
  # 预演模式（plan）除外 —— 预演本来就不改系统，仍要显示对比信息。
  if [ "$MODE" = apply ]; then
    if ! php_upgrade_needed; then
      ok "已是最新：本机 $(current_php_version)，仓库最新 $(target_php_version)，无需升级"
      log "  ${C_D}想强制重装/修复扩展: sudo $PM reinstall 'php*'${C_N}"
      return 0
    fi
  fi

  if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
    log ""
    # 分支没变的时候，别再说"升级到 X"——那会让人以为要跨大版本。
    # 实测踩过的场景：已在 remi-8.5，还提示"即将把 PHP 升级到 8.5"。
    # 同时把**具体版本号**摆出来，否则"小版本更新"看不出到底从几升到几。
    vcur=$(current_php_version)
    vnew=$(target_php_version)
    if [ "$PM" = dnf ] && [ "$CUR_STREAM" = "remi-$TARGET" ]; then
      info "当前已在 PHP $TARGET 分支（stream: $CUR_STREAM），本次是分支内小版本更新"
      if [ -n "$vcur" ] && [ -n "$vnew" ]; then
        warn "即将把 PHP 从 $vcur 更新到 $vnew（$PRETTY_OS）"
      else
        warn "即将更新 PHP $TARGET 及其扩展到仓库中的最新版本（$PRETTY_OS）"
      fi
    else
      if [ -n "$vcur" ] && [ -n "$vnew" ]; then
        warn "即将把 PHP 从 ${vcur:-未安装} 更新到 $vnew（$PRETTY_OS）"
      else
        warn "即将把 PHP 升级到 $TARGET（$PRETTY_OS），当前 stream: ${CUR_STREAM:-<无>}"
      fi
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
    # 完成提示必须给具体版本号。只说 "PHP 8.5" 看不出到底升到哪个 patch，
    # 用户还得自己跑 `php --version` 核对（实测反馈）。
    local vdone
    vdone=$(current_php_version)
    if [ -n "$vdone" ] && [ -n "$vcur" ] && [ "$vcur" != "$vdone" ]; then
      ok "升级完成：PHP $vcur → $vdone"
    elif [ -n "$vdone" ]; then
      ok "升级完成：PHP $vdone"
    else
      ok "升级完成：PHP $TARGET"
    fi
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
    mirror-epel)
      [ "$MIRROR" = official ] && { restore_epel_official; exit 0; }
      apply_epel_mirror "$MIRROR"; exit 0 ;;
    mirror-os) apply_os_mirror "$MIRROR"; exit 0 ;;
    audit)   audit_sys_repos; exit 0 ;;
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
    mirror)
      # 注意：main 在函数外，不能用 local
      log ""
      show_remi_bench
      log ""
      log "  ${C_B}选择要使用的 Remi 源${C_N}  ${C_D}（耗时为本机刚才实测）${C_N}"
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
    mirror-epel)
      # 注意：main 在函数外，不能用 local
      log ""
      show_epel_bench
      log ""
      log "  ${C_B}选择要使用的 EPEL 源${C_N}  ${C_D}（耗时为本机刚才实测）${C_N}"
      log "    0) 返回"
      drain_input
      printf "请选择 [0-5]: "
      read -r mc || exit 0
      case "$mc" in
        1) restore_epel_official ;;
        2) apply_epel_mirror tuna ;;
        3) apply_epel_mirror ustc ;;
        4) apply_epel_mirror aliyun ;;
        5) apply_epel_mirror huawei ;;
        *) info "已返回" ;;
      esac
      ;;
    mirror-os)
      log ""
      show_os_bench
      log ""
      log "  ${C_B}选择要使用的 CentOS 官方源${C_N}  ${C_D}（耗时为本机刚才实测 BaseOS）${C_N}"
      log "    0) 返回"
      drain_input
      printf "请选择 [0-6]: "
      read -r mc || exit 0
      case "$mc" in
        1) apply_os_mirror tencent ;;
        2) apply_os_mirror tuna ;;
        3) apply_os_mirror ustc ;;
        4) apply_os_mirror aliyun ;;
        5) apply_os_mirror huawei ;;
        6) apply_os_mirror official ;;
        *) info "已返回" ;;
      esac
      ;;
    audit)
      audit_sys_repos
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
