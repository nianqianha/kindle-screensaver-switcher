#!/bin/sh
# Kindle 端屏保管理 agent：PC 只发参数，rm/mntroot/sha256sum 都在设备端执行。
DIR=/var/local/custom_screensavers
op="$1"; n="$2"
case "$op" in
  # 自动识别机型：从系统原生屏保 PNG 头读屏幕尺寸（不用用户选机型）
  detect)
    png=""
    for f in /usr/share/blanket/screensaver/bg_ss00.png /usr/share/blanket/screensaver/bg_kcblackbackground.jpg /usr/share/blanket/screensaver/*.png; do
      [ -f "$f" ] && { png="$f"; break; }
    done
    size=""
    case "$png" in
      *.png) size=$(lua -e '
        local f=io.open("'"$png"'","rb"); if not f then return end
        f:seek("set",16)
        local function u32() local a,b,c,d=f:read(1),f:read(1),f:read(1),f:read(1); return string.byte(a)*16777216+string.byte(b)*65536+string.byte(c)*256+string.byte(d) end
        local w=u32(); local h=u32(); f:close(); print(w.."x"..h)' 2>/dev/null) ;;
    esac
    model=$(cat /proc/usid 2>/dev/null | cut -c1-6)
    echo "SIZE=${size:-unknown}"
    echo "MODEL=${model:-unknown}"
    echo "COUNT=$(ls -1 $DIR/bg_ss*.png 2>/dev/null | wc -l)" ;;
  list) ls -1 $DIR/bg_ss*.png 2>/dev/null | sed 's|.*/||' ;;
  remove)
    name=$(printf 'bg_ss%02d.png' "$n")
    mntroot rw
    rm -f "$DIR/$name"
    mntroot ro
    if [ -e "$DIR/$name" ]; then echo "FAIL $name still exists"; else echo "OK removed $name"; fi ;;
  install)
    # 从 /var/tmp 安装已上传的 PNG 到屏保目录
    name=$(printf 'bg_ss%02d.png' "$n")
    mntroot rw
    cp "/var/tmp/$name" "$DIR/$name"
    mntroot ro
    sha256sum "$DIR/$name" ;;
  *) echo "usage: kss-agent.sh list|remove N|install N" ;;
esac
