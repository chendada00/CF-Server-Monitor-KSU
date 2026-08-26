#!/system/bin/sh

MODDIR="${0%/*}"
MANAGER="$MODDIR/scripts/manager.sh"

# 强制开启调试输出
set -x
exec 2>&1

echo "========================================"
echo "CF Server Monitor - 音量键控制版"
echo "脚本启动时间: $(date)"
echo "========================================"

# 函数：打印日志
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log "开始初始化..."

# 检查manager.sh是否存在
if [ ! -f "$MANAGER" ]; then
    log "错误: manager.sh 不存在于 $MANAGER"
    exit 1
fi
log "找到 manager.sh: $MANAGER"

# 使用getevent直接检测（最可靠的方式）
log "使用 getevent 方式检测音量键..."

# 创建临时文件存储事件
TEMP_EVENT="/tmp/volume_event_$$"
log "临时文件: $TEMP_EVENT"

# 获取音量键事件码的函数
get_volume_events() {
    log "正在检测音量键事件码..."
    
    # 启动getevent并过滤
    log "请按音量+或音量-键测试..."
    log "等待按键输入（5秒超时）..."
    
    # 使用getevent获取事件
    local result=$(timeout 5 getevent 2>/dev/null | grep -m 1 -E "KEY_VOLUMEUP|KEY_VOLUMEDOWN|00000073|00000072" | head -1)
    
    if [ -n "$result" ]; then
        log "检测到按键: $result"
        echo "$result" > "$TEMP_EVENT"
        return 0
    else
        log "未检测到音量键"
        return 1
    fi
}

# 简单的菜单显示（不依赖任何特殊命令）
show_menu() {
    local selected=$1
    local options=(
        "启动服务"
        "停止服务"
        "重启服务"
        "查看状态"
        "查看日志"
        "查看版本"
        "退出"
    )
    
    echo ""
    echo "========================================"
    echo "      CF Server Monitor"
    echo "========================================"
    echo "  操作说明:"
    echo "  音量+ : 切换到下一个选项"
    echo "  音量- : 执行选中的操作"
    echo "========================================"
    
    for i in "${!options[@]}"; do
        if [ $i -eq $selected ]; then
            echo "  ▶ [$((i+1))] ${options[$i]}  ← 当前选中"
        else
            echo "    [$((i+1))] ${options[$i]}"
        fi
    done
    echo "========================================"
    echo "  当前选中: ${options[$selected]}"
    echo "  按 音量- 执行"
    echo "========================================"
}

# 等待按键（简化版）
wait_for_key() {
    local timeout=${1:-1}
    local result=""
    
    # 使用getevent读取按键
    result=$(timeout "$timeout" getevent -l 2>/dev/null | grep -m 1 -E "KEY_VOLUMEUP|KEY_VOLUMEDOWN" | awk '{print $NF}')
    
    echo "$result"
}

# 确认对话框
confirm_action() {
    local action="$1"
    local count=0
    
    echo ""
    echo "========================================"
    echo "  ⚠️  确认执行: $action"
    echo "========================================"
    echo "  按 音量- 确认  按 音量+ 取消"
    echo ""
    echo -n "  等待确认"
    
    while [ $count -lt 8 ]; do
        local key=$(wait_for_key 0.3)
        
        case "$key" in
            KEY_VOLUMEDOWN)
                echo ""
                echo "  ✅ 已确认，正在执行..."
                return 0
                ;;
            KEY_VOLUMEUP)
                echo ""
                echo "  ❌ 已取消"
                return 1
                ;;
        esac
        
        count=$((count + 1))
        echo -n "."
        sleep 0.3
    done
    
    echo ""
    echo "  ⏰ 操作超时，已取消"
    return 1
}

# 执行操作
execute_action() {
    local action_index=$1
    
    echo ""
    echo "========================================"
    echo "  执行结果："
    echo "========================================"
    
    case $action_index in
        0) 
            log "执行: 启动服务"
            /system/bin/sh "$MANAGER" start
            ;;
        1) 
            log "执行: 停止服务"
            /system/bin/sh "$MANAGER" stop
            ;;
        2) 
            log "执行: 重启服务"
            /system/bin/sh "$MANAGER" restart
            ;;
        3) 
            log "执行: 查看状态"
            /system/bin/sh "$MANAGER" status
            ;;
        4) 
            log "执行: 查看日志"
            /system/bin/sh "$MANAGER" logs
            ;;
        5) 
            log "执行: 查看版本"
            /system/bin/sh "$MANAGER" version
            ;;
        6) 
            log "退出程序"
            exit 0
            ;;
    esac
    
    echo "========================================"
}

# 主循环
main_loop() {
    local selected=0
    local total_options=7
    
    log "进入主循环..."
    log "提示: 按音量+切换选项，按音量-执行操作"
    
    # 先显示一次菜单
    show_menu $selected
    
    while true; do
        # 等待按键
        local key=$(wait_for_key 0.5)
        
        case "$key" in
            KEY_VOLUMEUP)
                # 音量+ 切换到下一个
                selected=$((selected + 1))
                if [ $selected -ge $total_options ]; then
                    selected=0
                fi
                show_menu $selected
                ;;
            KEY_VOLUMEDOWN)
                # 音量- 确认选择
                local action_name=""
                case $selected in
                    0) action_name="启动服务" ;;
                    1) action_name="停止服务" ;;
                    2) action_name="重启服务" ;;
                    3) action_name="查看状态" ;;
                    4) action_name="查看日志" ;;
                    5) action_name="查看版本" ;;
                    6) action_name="退出" ;;
                esac
                
                if confirm_action "$action_name"; then
                    execute_action $selected
                    if [ $selected -ne 6 ]; then
                        echo ""
                        echo "按任意音量键继续..."
                        wait_for_key 2 > /dev/null
                        show_menu $selected
                    fi
                else
                    show_menu $selected
                fi
                ;;
        esac
        
        sleep 0.1
    done
}

# 主入口
log "脚本参数: $*"

case "$1" in
    menu|"")
        log "启动音量键交互模式..."
        main_loop
        ;;
    start|1)
        log "执行: 启动服务"
        /system/bin/sh "$MANAGER" start
        ;;
    stop|2)
        log "执行: 停止服务"
        /system/bin/sh "$MANAGER" stop
        ;;
    restart|3)
        log "执行: 重启服务"
        /system/bin/sh "$MANAGER" restart
        ;;
    status|4)
        log "执行: 查看状态"
        /system/bin/sh "$MANAGER" status
        ;;
    logs|5)
        log "执行: 查看日志"
        /system/bin/sh "$MANAGER" logs
        ;;
    version|6)
        log "执行: 查看版本"
        /system/bin/sh "$MANAGER" version
        ;;
    *)
        echo "CF Server Monitor"
        echo "Usage:"
        echo "  menu           - 音量键交互菜单"
        echo "  start|1        - 启动服务"
        echo "  stop|2         - 停止服务"
        echo "  restart|3      - 重启服务"
        echo "  status|4       - 查看状态"
        echo "  logs|5         - 查看日志"
        echo "  version|6      - 查看版本"
        ;;
esac

log "脚本执行完毕"