#!/bin/bash
# 定时设置：*/10 * * * * /bin/bash /root/kp.sh 每10分钟运行一次
# 如果你已安装了Serv00本地SSH脚本，不要再运行此脚本部署了，这样会造成进程爆满，必须二选一！
# serv00变量添加规则：
# 如使用保活网页，请不要启用cron，以防止cron与网页保活重复运行造成进程爆满
# RES(必填)：n表示每次不重置部署，y表示每次重置部署。REP(必填)：n表示不重置随机端口(三个端口留空)，y表示重置端口(三个端口留空)。SSH_USER(必填)表示serv00账号名。SSH_PASS(必填)表示serv00密码。REALITY表示reality域名(留空表示serv00官方域名：你serv00账号名.serv00.net)。SUUID表示uuid(留空表示随机uuid)。TCP1_PORT表示vless的tcp端口(留空表示随机tcp端口)。TCP2_PORT表示vmess的tcp端口(留空表示随机tcp端口)。UDP_PORT表示hy2的udp端口(留空表示随机udp端口)。HOST(必填)表示登录serv00服务器域名。ARGO_DOMAIN表示argo固定域名(留空表示临时域名)。ARGO_AUTH表示argo固定域名token(留空表示临时域名)。
# 必填变量：RES、REP、SSH_USER、SSH_PASS、HOST
# 注意[]"",:这些符号不要乱删，按规律对齐
# 每行一个{serv00服务器}，一个服务也可，末尾用,间隔，最后一个服务器末尾无需用,间隔
if [ -z "${ACCOUNTS:-}" ]; then
ACCOUNTS='[
{"RES":"n", "REP":"n", "SSH_USER":"你的serv00账号名", "SSH_PASS":"你的serv00账号密码", "REALITY":"你的Reality域名", "SUUID":"自设UUID", "TCP1_PORT":"", "TCP2_PORT":"", "UDP_PORT":"", "HOST":"你的Serv00主机名", "ARGO_DOMAIN":"", "ARGO_AUTH":""}
]'
fi
run_remote_command() {
local RES=$1
local REP=$2
local SSH_USER=$3
local SSH_PASS=$4
local REALITY=${5}
local SUUID=$6
local TCP1_PORT=$7
local TCP2_PORT=$8
local UDP_PORT=$9
local HOST=${10}
local ARGO_DOMAIN=${11}
local ARGO_AUTH=${12}
local script_root keep_script asset
script_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
keep_script="$script_root/serv00keep.sh"
for asset in serv00keep.sh app.js index.html; do
  [ -r "$script_root/$asset" ] || {
    echo "缺少本地 $asset，拒绝从未校验的远程分支直接执行" >&2
    return 1
  }
done
  if [ -z "${ARGO_DOMAIN}" ]; then
    echo "Argo域名为空，申请Argo临时域名"
  else
    echo "Argo已设置固定域名：${ARGO_DOMAIN}"
  fi
  echo "正在安全部署 $HOST（敏感参数不会写入命令行或日志）"
  tar -czf - -C "$script_root" serv00keep.sh app.js index.html | \
    SSHPASS="$SSH_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new \
      "$SSH_USER@$HOST" \
      'umask 077; mkdir -p "$HOME/.local/share/sing-box-yg"; tar -xzf - -C "$HOME/.local/share/sing-box-yg"; chmod 700 "$HOME/.local/share/sing-box-yg/serv00keep.sh"'
  {
    printf 'export reym=%q UUID=%q vless_port=%q vmess_port=%q hy2_port=%q reset=%q resport=%q ARGO_DOMAIN=%q ARGO_AUTH=%q\n' \
      "$REALITY" "$SUUID" "$TCP1_PORT" "$TCP2_PORT" "$UDP_PORT" "$RES" "$REP" "$ARGO_DOMAIN" "$ARGO_AUTH"
    printf 'export SBYG_ASSET_DIR="$HOME/.local/share/sing-box-yg"\n'
    printf 'bash "$SBYG_ASSET_DIR/serv00keep.sh"\n'
  } | SSHPASS="$SSH_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new "$SSH_USER@$HOST" 'bash -s'
}
sbyg_ssh() {
  local password=$1
  shift
  SSHPASS="$password" sshpass -e ssh -o StrictHostKeyChecking=accept-new "$@"
}
if  cat /etc/issue /proc/version /etc/os-release 2>/dev/null | grep -q -E -i "openwrt"; then
opkg update
opkg install sshpass curl jq
else
    if [ -f /etc/debian_version ]; then
        package_manager="apt-get install -y"
        apt-get update >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        package_manager="yum install -y"
    elif [ -f /etc/fedora-release ]; then
        package_manager="dnf install -y"
    elif [ -f /etc/alpine-release ]; then
        package_manager="apk add"
    fi
    $package_manager sshpass curl jq cron >/dev/null 2>&1
fi
echo "*****************************************************"
echo "*****************************************************"
echo "维护仓库：github.com/reqingonline/sing-box-yg"
echo "自动远程部署Serv00三合一协议脚本【VPS+软路由】"
echo "版本：V25.3.26"
echo "*****************************************************"
echo "*****************************************************"
              count=0  
           for account in $(echo "${ACCOUNTS}" | jq -c '.[]'); do
              count=$((count+1))
              RES=$(echo $account | jq -r '.RES')
              REP=$(echo $account | jq -r '.REP')              
              SSH_USER=$(echo $account | jq -r '.SSH_USER')
              SSH_PASS=$(echo $account | jq -r '.SSH_PASS')
              REALITY=$(echo $account | jq -r '.REALITY')
              SUUID=$(echo $account | jq -r '.SUUID')
              TCP1_PORT=$(echo $account | jq -r '.TCP1_PORT')
              TCP2_PORT=$(echo $account | jq -r '.TCP2_PORT')
              UDP_PORT=$(echo $account | jq -r '.UDP_PORT')
              HOST=$(echo $account | jq -r '.HOST')
              ARGO_DOMAIN=$(echo $account | jq -r '.ARGO_DOMAIN')
              ARGO_AUTH=$(echo $account | jq -r '.ARGO_AUTH') 
          if sbyg_ssh "$SSH_PASS" "$SSH_USER@$HOST" -q exit; then
            echo "🎉恭喜！✅第【$count】台服务器连接成功！🚀服务器地址：$HOST ，账户名：$SSH_USER"   
          if [ -z "${ARGO_DOMAIN}" ]; then
           check_process="ps aux | grep '[c]onfig' > /dev/null && ps aux | grep [l]ocalhost:$TCP2_PORT > /dev/null"
            else
           check_process="ps aux | grep '[c]onfig' > /dev/null && ps aux | grep '[c]loudflared.*tunnel' > /dev/null"
           fi
          if ! sbyg_ssh "$SSH_PASS" "$SSH_USER@$HOST" "$check_process" || [[ "$RES" =~ ^[Yy]$ ]]; then
            echo "⚠️检测到主进程或者argo进程未启动，或者执行重置"
             echo "⚠️现在开始修复或重置部署……请稍等"
             output=$(run_remote_command "$RES" "$REP" "$SSH_USER" "$SSH_PASS" "${REALITY}" "$SUUID" "$TCP1_PORT" "$TCP2_PORT" "$UDP_PORT" "$HOST" "${ARGO_DOMAIN}" "${ARGO_AUTH}")
            echo "远程命令执行结果：$output"
          else
            echo "🎉恭喜！✅检测到所有进程正常运行中 "
            SSH_USER_LOWER=$(echo "$SSH_USER" | tr '[:upper:]' '[:lower:]')
            sbyg_ssh "$SSH_PASS" "$SSH_USER@$HOST" "
            echo \"配置显示如下：\"
            cat domains/${SSH_USER_LOWER}.serv00.net/logs/list.txt
            echo \"====================================================\""
            fi
           else
            echo "===================================================="
            echo "💥杯具！❌第【$count】台服务器连接失败！🚀服务器地址：$HOST ，账户名：$SSH_USER"
            echo "⚠️可能账号名、密码、服务器名称输入错误，或者当前服务器在维护中"  
            echo "===================================================="
           fi
            done
