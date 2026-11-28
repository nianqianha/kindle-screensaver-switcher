#!/bin/sh
# Kindle 端屏保管理 agent（2026-11-28 通用化重写）。
# PC 只发参数；rm/mntroot/sha256sum 都在设备端执行，规避卡巴 PDM 行为误报。
#
# 通用化要点：
#   1) 路线参数化：A=系统 blanket /var/local/custom_screensavers（需 mntroot rw）
#                  B=MobileRead hack /mnt/us/screensavers（用户分区，无需 mntroot）
#                  目录由 detect 探测；不写死单一路径。
#   2) 热自愈：任何写操作开始前检查根分区是否已被上次 SIGKILL/断电留在 rw，
#              若是先 mntroot ro 恢复；把 rw 持有窗口压到最小。
#   3) 锁用 PID+时间戳：kill -0 验证持有者存活，杜绝抢占活锁与「无 started 永久死锁」。
#   4) 原子写入：先写 .tmp 再 mv 覆盖，避免半张图。
#   5) 尺寸探测链：stock PNG 头 → fb0 virtual_size → usid 码表；JPG 候选不再误入 PNG 分支。
#   6) staging 唯一名（$$），消除 scp→install 的 TOCTOU。
#   7) detect 输出 MODEL/SIZE/COUNT/ROUTE/BLANKET/FW 供 kss conn 体检。

DIR_A=/var/local/custom_screensavers
DIR_B=/mnt/us/screensavers
LOCK_FILE=/var/tmp/.kss-agent.lock
STALE_SEC=60
MOUNTED_RW=0
LOCK_HELD=0

cleanup() {
    if [ "$MOUNTED_RW" = "1" ]; then mntroot ro >/dev/null 2>&1; MOUNTED_RW=0; fi
    # 锁是 mkdir 创建的目录：用 rmdir 删（只删空目录，比 rm -rf 安全）；owner 是普通文件先删
    if [ "$LOCK_HELD" = "1" ]; then
        rm -f "$LOCK_FILE/owner" 2>/dev/null
        rmdir "$LOCK_FILE" 2>/dev/null
        LOCK_HELD=0
    fi
}
trap 'cleanup' EXIT
trap 'cleanup; exit 1' INT TERM HUP
die() { echo "ERR $*"; exit 1; }

# 依据路线参数解析目标目录（严格白名单）
resolve_dir() {
    case "$1" in
        A|a|"") echo "$DIR_A" ;;
        B|b)    echo "$DIR_B" ;;
        *) die "路线无效（A/B）" ;;
    esac
}

# 索引严格校验 0-99
validate_index() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$1" -ge 0 ] 2>/dev/null && [ "$1" -le 99 ] 2>/dev/null
}

# 自动探测该用哪条路线：B 目录有图且 A 没有 → B；否则 A
detect_route() {
    if [ -d "$DIR_B" ] && ls -1 "$DIR_B"/bg_ss*.png "$DIR_B"/*.png 2>/dev/null | grep -q .; then
        if ! ls -1 "$DIR_A"/bg_ss*.png 2>/dev/null | grep -q .; then echo "B"; return; fi
    fi
    echo "A"
}

# 从 PNG IHDR(偏移16) 读宽高，做范围校验（64-4096），异常输出空
png_size() {
    KSS_PNG="$1" lua -e '
      local f=io.open(os.getenv("KSS_PNG"),"rb"); if not f then return end
      local hdr=f:read(8); if hdr ~= "\137PNG\r\n\26\n" then f:close() return end
      f:seek("set",16)
      local function u32() local a,b,c,d=f:read(1),f:read(1),f:read(1),f:read(1)
        if not (a and b and c and d) then return 0 end
        return string.byte(a)*16777216+string.byte(b)*65536+string.byte(c)*256+string.byte(d) end
      local w=u32(); local h=u32(); f:close()
      if w>=64 and w<=4096 and h>=64 and h<=4096 then print(w.."x"..h) end' 2>/dev/null
}

# usid 前缀 → 尺寸（兜底，免 root）
usid_size() {
    id=$(cat /proc/usid 2>/dev/null | cut -c1-6)
    case "$id" in
        G092*|G090*) echo "1072x1448" ;;
        908*) echo "1072x1448" ;;
        B0*|90*) echo "600x800" ;;
        *) ;;
    esac
}

# 锁：mkdir 成功后才把路径写入全局（避免杀在窗口里 cleanup 误删别人的锁）；
# 锁文件内容="PID 时间戳"，抢锁时 kill -0 验证存活。
acquire_lock() {
    local_dir="$LOCK_FILE"
    lock_parent=$(dirname "$local_dir")
    [ -d "$lock_parent" ] || die "锁父路径 $lock_parent 不存在"
    if mkdir "$local_dir" 2>/dev/null; then
        LOCK_FILE="$local_dir"; LOCK_HELD=1
        echo "$$ $(date +%s 2>/dev/null)" > "$LOCK_FILE/owner"
        return
    fi
    owner=$(cat "$LOCK_FILE/owner" 2>/dev/null)
    pid=$(echo "$owner" | awk '{print $1}')
    ts=$(echo "$owner" | awk '{print $2}')
    now=$(date +%s 2>/dev/null)
    alive=0
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=1
    if [ "$alive" = "1" ] && { [ -z "$ts" ] || [ $((now - ts)) -le "$STALE_SEC" ]; }; then
        die "另一个 kss-agent 正在运行（PID $pid）"
    fi
    # 持有者已死或锁超过阈值未更新 → 安全接管（只删 owner 文件 + 空目录）
    rm -f "$LOCK_FILE/owner" 2>/dev/null
    rmdir "$LOCK_FILE" 2>/dev/null || die "锁目录非空，拒绝接管（可能有残留数据）"
    mkdir "$LOCK_FILE" 2>/dev/null || die "锁接管失败"
    LOCK_HELD=1
    echo "$$ $now" > "$LOCK_FILE/owner"
}

# 进入写操作前自愈：如果根分区已被留在 rw，先恢复 ro
ensure_ro() {
    if grep -q ' / .* rw[ ,]' /proc/mounts 2>/dev/null; then
        mntroot ro >/dev/null 2>&1
    fi
}
mount_rw() { mntroot rw >/dev/null 2>&1 || die "mntroot rw 失败"; MOUNTED_RW=1; }
mount_ro() { mntroot ro >/dev/null 2>&1 || die "mntroot ro 失败"; MOUNTED_RW=0; }

op="$1"; n="$2"; route="${3:-}"; staging="${4:-}"

case "$op" in
  detect)
    # 尺寸探测链：stock PNG → fb0 → usid
    size=""
    for f in /usr/share/blanket/screensaver/bg_ss00.png /usr/share/blanket/screensaver/*.png; do
        [ -f "$f" ] || continue
        size=$(png_size "$f")
        [ -n "$size" ] && break
    done
    [ -z "$size" ] && [ -r /sys/class/graphics/fb0/virtual_size ] && {
        v=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
        case "$v" in *,*) w=${v%,*}; h=${v#*,};
            [ "$w" -ge 64 ] 2>/dev/null && [ "$w" -le 4096 ] 2>/dev/null &&
            [ "$h" -ge 64 ] 2>/dev/null && [ "$h" -le 4096 ] 2>/dev/null && size="$w x $h" ;; esac
    }
    [ -z "$size" ] && size=$(usid_size)
    model=$(cat /proc/usid 2>/dev/null | cut -c1-6)
    r=$(detect_route)
    dir=$(resolve_dir "$r")
    blanket=$(lipc-get-prop com.lab126.blanket load 2>/dev/null)
    # 固件版本：多来源兜底（不同固件放不同位置）
    fw=""
    for vf in /etc/system-version /etc/.system-version /var/local/system-version; do
        [ -f "$vf" ] && { fw=$(head -1 "$vf" 2>/dev/null); break; }
    done
    [ -z "$fw" ] && fw=$(grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' /etc/os-release 2>/dev/null)
    count=$(set -- "$dir"/bg_ss*.png 2>/dev/null; if [ -e "$1" ]; then echo $#; else echo 0; fi)
    echo "SIZE=${size:-unknown}"
    echo "MODEL=${model:-unknown}"
    echo "ROUTE=$r"
    echo "DIR=$dir"
    echo "COUNT=$count"
    echo "BLANKET=${blanket:-unknown}"
    echo "FW=${fw:-unknown}"
    echo "AGENT_VER=2" ;;
  list)
    dir=$(resolve_dir "$route")
    ls -1 "$dir"/bg_ss*.png 2>/dev/null | sed 's|.*/||' ;;
  remove)
    validate_index "$n" || die "编号无效（需 0-99）"
    dir=$(resolve_dir "$route")
    name=$(printf 'bg_ss%02d.png' "$n")
    [ -e "$dir/$name" ] || die "文件不存在 $dir/$name"
    acquire_lock; ensure_ro
    if [ "$dir" = "$DIR_A" ]; then mount_rw; fi
    rm -f "$dir/$name" || { [ "$dir" = "$DIR_A" ] && mount_ro; die "rm 失败"; }
    [ "$dir" = "$DIR_A" ] && mount_ro
    echo "OK removed $dir/$name" ;;
  install)
    validate_index "$n" || die "编号无效（需 0-99）"
    dir=$(resolve_dir "$route")
    name=$(printf 'bg_ss%02d.png' "$n")
    src="$staging"
    [ -z "$src" ] && src="/var/tmp/$name"
    [ -f "$src" ] || die "源文件不存在 $src"
    acquire_lock; ensure_ro
    if [ "$dir" = "$DIR_A" ]; then mount_rw; fi
    cp "$src" "$dir/$name.tmp" || { [ "$dir" = "$DIR_A" ] && mount_ro; die "cp 失败"; }
    mv -f "$dir/$name.tmp" "$dir/$name" || { rm -f "$dir/$name.tmp"; [ "$dir" = "$DIR_A" ] && mount_ro; die "mv 失败"; }
    [ "$dir" = "$DIR_A" ] && mount_ro
    rm -f "$src" 2>/dev/null
    sha256sum "$dir/$name" ;;
  *) echo "usage: kss-agent.sh detect|list [A|B]|remove N [A|B]|install N [A|B] [staging]" ;;
esac
