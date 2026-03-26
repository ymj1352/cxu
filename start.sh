#!/bin/sh
set -e


# 环境变量
CLOUDFLARED_TOKEN="${TOKEN:-}"
UUID="${UUID:-12345678}"
SSH_PASSWORD="${SSH:-88888888}"
DIRECT="${DIRECT:-false}"


# 全局变量初始化
CLOUDFLARED_PID=""
USQUE_PID=""
XTUNNEL_PID=""
SSH_PID=""
CLOUDFLARED_LOG=""
USQUE_LOG=""
XTUNNEL_LOG=""
SSH_LOG=""

# ==========================
# 检查并设置可执行权限
# ==========================
echo "设置可执行权限.."

# 递归设置 /app 目录下所有可执行文件权限
if [ -d "/app" ]; then
    find /app -type f -name "cloudflared" -o -name "usque" -o -name "x-tunnel" | xargs -I {} chmod +x {} 2>/dev/null || true
    echo "可执行权限设置完成"
else
    echo "警告: /app 目录不存在"
fi

# ==========================
# 启动 CLOUDFLARED
# ==========================
echo "=========================="
echo "启动 CLOUDFLARED [1/3]..."
echo "=========================="
if [ -f "/app/cloudflared/cloudflared" ]; then
    rm -f /tmp/cloudflared.log
    if [ -z "$CLOUDFLARED_TOKEN" ]; then
        echo "未设置 TOKEN 环境变量，使用临时隧道模式..."
        echo "临时隧道将指向 x-tunnel 服务 (localhost:8080)"
        /app/cloudflared/cloudflared tunnel --url http://localhost:8080 >/tmp/cloudflared.log 2>&1 &
        
        CLOUDFLARED_PID=$!
        CLOUDFLARED_LOG="/tmp/cloudflared.log"
        echo "CLOUDFLARED 已启动，PID: $CLOUDFLARED_PID"
        
        # 等待临时隧道域名生成
        echo "等待临时隧道域名生成..."
        sleep 5
        
        if ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
            echo "CLOUDFLARED 服务运行正常"
            # 提取并输出临时域名
            TUNNEL_URL=$(grep -oE 'https://[^[:space:]]+\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
            if [ -n "$TUNNEL_URL" ]; then
                echo "========================================"
                echo "临时隧道域名: $TUNNEL_URL"
                echo "========================================"
            else
                echo "临时隧道域名正在生成中，可查看日志获取:"
                grep -E 'trycloudflare\.com|Registered tunnel|INF|conn' /tmp/cloudflared.log | head -5
            fi
        else
            echo "警告: CLOUDFLARED 进程可能已退出"
            cat /tmp/cloudflared.log 2>/dev/null || echo "无法读取日志文件"
        fi
    else
        echo "使用 TOKEN 启动隧道..."
        /app/cloudflared/cloudflared tunnel run --token "$CLOUDFLARED_TOKEN" >/tmp/cloudflared.log 2>&1 &
        
        CLOUDFLARED_PID=$!
        CLOUDFLARED_LOG="/tmp/cloudflared.log"
        echo "CLOUDFLARED 已启动，PID: $CLOUDFLARED_PID"
        
        # 检查进程状态
        sleep 5
        
        if ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
            echo "CLOUDFLARED 服务运行正常"
            # 检查连接状态
            if grep -qi "error\|fatal\|fail" /tmp/cloudflared.log 2>/dev/null; then
                echo "警告: CLOUDFLARED 日志中可能包含错误信息"
                grep -i "error\|fatal\|fail" /tmp/cloudflared.log | head -3
            fi
        else
            echo "警告: CLOUDFLARED 进程可能已退出"
            cat /tmp/cloudflared.log 2>/dev/null || echo "无法读取日志文件"
        fi
    fi
else
    echo "错误: CLOUDFLARED 可执行文件不存在"
fi

# ==========================
# 启动 USQUE
# ==========================
echo "=========================="
echo "启动 USQUE [2/3]..."
echo "=========================="
if [ -f "/app/usque/usque" ]; then
    # 检查 usque 是否需要注册
    if [ ! -f "/app/usque/config.json" ]; then
        echo "USQUE 配置文件不存在，正在自动注册..."
        # 在 usque 目录下执行注册以生成正确的 config.json
        yes | /app/usque/usque register --workdir /app/usque >/app/usque/register.log 2>&1 || yes | (cd /app/usque && /app/usque/usque register) >/app/usque/register.log 2>&1
        echo "USQUE 自动注册完成或无需进一步操作"
    fi
    
    # 启动 usque
    rm -f /tmp/usque.log
    (cd /app/usque && ./usque socks -p 10003) >/tmp/usque.log 2>&1 &
    USQUE_PID=$!
    USQUE_LOG="/tmp/usque.log"
    echo "USQUE 已启动，PID: $USQUE_PID"
    
    # 检查进程状态
    sleep 4
    
    if ps -p $USQUE_PID > /dev/null 2>&1; then
        echo "USQUE 服务运行正常"
    else
        echo "警告: USQUE 进程可能已退出"
        cat /tmp/usque.log 2>/dev/null || echo "无法读取日志文件"
    fi
else
    echo "错误: USQUE 可执行文件不存在"
fi

# ==========================
# 启动 X_TUNNEL (服务器模式)
# ==========================
echo "=========================="
echo "启动 X_TUNNEL (服务器模式) [3/3]..."
echo "=========================="
if [ -f "/app/x-tunnel/x-tunnel" ]; then
    # 构建启动参数
    XTUNNEL_ARGS="-l ws://0.0.0.0:8080 -token $UUID"
    
    # 根据 DIRECT 环境变量决定是否添加 -f 参数
    if [ "$DIRECT" = "false" ]; then
        XTUNNEL_ARGS="$XTUNNEL_ARGS -f socks5://127.0.0.1:10003"
        echo "DIRECT 模式: 使用代理转发 (-f socks5://127.0.0.1:10003)"
    else
        echo "DIRECT 模式: 直接连接 (无 -f 参数)"
    fi
    
    echo "X_TUNNEL 参数: $XTUNNEL_ARGS"
    
    # 启动 x-tunnel（在 x-tunnel 目录下执行，使用规范的相对路径）
    rm -f /tmp/x-tunnel.log
    (cd /app/x-tunnel && ./x-tunnel $XTUNNEL_ARGS) >/tmp/x-tunnel.log 2>&1 &
    XTUNNEL_PID=$!
    XTUNNEL_LOG="/tmp/x-tunnel.log"
    echo "X_TUNNEL 已启动，PID: $XTUNNEL_PID"
    
    # 检查 x-tunnel 是否能正常执行
    sleep 1
    if ! ps -p $XTUNNEL_PID > /dev/null 2>&1; then
        # 进程退出，检查是否是库依赖问题
        if grep -q "not found\|No such file or directory" /tmp/x-tunnel.log 2>/dev/null; then
            echo "检测到 x-tunnel 执行失败，尝试其他方式启动..."
            kill $XTUNNEL_PID 2>/dev/null || true
            rm -f /tmp/x-tunnel.log
            /app/x-tunnel/x-tunnel $XTUNNEL_ARGS >/tmp/x-tunnel.log 2>&1 &
            XTUNNEL_PID=$!
            sleep 1
        fi
    fi
    
    # 简化的健康检查
    sleep 2
    if ps -p $XTUNNEL_PID > /dev/null 2>&1; then
        echo "X_TUNNEL 服务运行正常"
        # 检查是否有错误日志
        if grep -qi "error\|fatal\|fail" /tmp/x-tunnel.log 2>/dev/null; then
            echo "警告: X_TUNNEL 日志中可能包含错误信息"
        fi
    else
        echo "警告: X_TUNNEL 启动失败"
        cat /tmp/x-tunnel.log 2>/dev/null || echo "无法读取日志文件"
        # 尝试诊断问题
        echo "诊断信息："
        ldd /app/x-tunnel/x-tunnel 2>&1 | head -5
    fi
else
    echo "错误: X_TUNNEL 可执行文件不存在"
fi

# ==========================
# 启动 SSH 服务
# ==========================
echo "=========================="
echo "启动 SSH 服务 [4/4]..."
echo "=========================="

# 检查 sshd 是否可用
if command -v /usr/sbin/sshd >/dev/null 2>&1; then
    # 配置 SSH
    mkdir -p /root/.ssh
    ssh-keygen -A 2>/dev/null
    
    # 修改配置允许密码登录
    if [ -f "/etc/ssh/sshd_config" ]; then
        sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    
    # 设置 root 密码
    echo "root:$SSH_PASSWORD" | chpasswd
    
    # 启动 SSH 服务
    rm -f /tmp/sshd.log
    /usr/sbin/sshd -D -E /tmp/sshd.log &
    SSH_PID=$!
    SSH_LOG="/tmp/sshd.log"
    echo "SSH 已启动，PID: $SSH_PID"
    echo "SSH root 密码: $SSH_PASSWORD"
    
    sleep 2
    if ps -p $SSH_PID > /dev/null 2>&1; then
        echo "SSH 服务运行正常，端口: 22"
    else
        echo "警告: SSH 服务启动失败"
        cat /tmp/sshd.log 2>/dev/null || echo "无法读取 SSH 日志文件"
    fi
else
    echo "警告: SSH 服务不可用，sshd 未安装"
fi

# ==========================
# 输出启动信息
# ==========================
echo "=========================="
echo "所有服务启动完成"
echo "=========================="
echo "启动顺序: CLOUDFLARED → USQUE → X_TUNNEL → SSH"
echo "--------------------------"
if [ -n "$CLOUDFLARED_PID" ]; then
    echo "CLOUDFLARED PID: $CLOUDFLARED_PID"
else
    echo "CLOUDFLARED PID: 未启动"
fi
if [ -n "$USQUE_PID" ]; then
    echo "USQUE PID: $USQUE_PID"
else
    echo "USQUE PID: 未启动"
fi
if [ -n "$XTUNNEL_PID" ]; then
    echo "X_TUNNEL PID: $XTUNNEL_PID"
else
    echo "X_TUNNEL PID: 未启动"
fi
if [ -n "$SSH_PID" ]; then
    echo "SSH PID: $SSH_PID"
    echo "SSH root 密码: $SSH_PASSWORD"
else
    echo "SSH PID: 未启动"
fi
echo "--------------------------"
echo "日志输出优先级: X_TUNNEL > USQUE > CLOUDFLARED"
echo "=========================="

# ==========================
# 日志前台输出
# ==========================
if [[ -n "$XTUNNEL_LOG" && -f "$XTUNNEL_LOG" ]]; then
    echo "正在查看 X_TUNNEL 日志..."
    tail -f "$XTUNNEL_LOG"
elif [[ -n "$USQUE_LOG" && -f "$USQUE_LOG" ]]; then
    echo "正在查看 USQUE 日志..."
    tail -f "$USQUE_LOG"
elif [[ -n "$CLOUDFLARED_LOG" && -f "$CLOUDFLARED_LOG" ]]; then
    echo "正在查看 CLOUDFLARED 日志..."
    tail -f "$CLOUDFLARED_LOG"
else
    echo "没有服务运行，退出..."
    exit 1
fi