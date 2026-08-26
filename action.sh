#!/system/bin/sh

MODDIR="${0%/*}"
MANAGER="$MODDIR/scripts/manager.sh"

# 颜色输出（可选）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取input设备（自动检测）
get_input_device() {
    # 尝试常见的input设备路径
    for dev in /dev/input/event0 /dev/input/event1 /dev/input/event2 /dev/input/event3; do
        if [ -e "$dev" ]; then
            # 检查是否是真正的输入设备（不是鼠标等）
            local dev_name=$(cat /proc/bus/input/devices 2>/dev/null | grep -A 5 "event$(echo $dev | sed 's/.*event//')" | grep "Name" | head -1)
            if echo "$dev_name" | grep -qi "volume\|keyboard\|gpio\|power"; then
                echo "$dev"
                return 0
            fi
        fi
    done
    # 如果找不到，默认使用event0
    echo "/dev/input/event0"
}

INPUT_DEVICE=$(get_input_device)

# 读取按键事件
read_key_event() {
    local timeout=${1:-0.5}
    # 使用dd读取固定字节，避免阻塞
    local event=$(timeout "$timeout" dd if="$INPUT_DEVICE" bs=24 count=1 2>/dev/null | hexdump -e '16/1 "%02x "')
    echo "$event"
}

# 检测按键码
# 音量+ 通常是 0x73 (KEY_VOLUMEUP)
# 音量- 通常是 0x72 (KEY_VOLUMEDOWN)
detect_volume_key() {
    local event_data="$1"
    local has_up=0
    local has_down=0
    
    if echo "$event_data" | grep -q "73"; then
        has_up=1
    fi
    if echo "$event_data" | grep -q "72"; then
        has_down=1
    fi
    
    if [ $has_up -eq 1 ] && [ $has_down -eq 0 ]; then
        echo "up"
    elif [ $has_up -eq 0 ] && [ $has_down -eq 1 ]; then
        echo "down"
    elif [ $has_up -eq 1 ] && [ $has_down -eq 1 ]; then
        echo "both"
    else
        echo "none"
    fi
}

# 显示菜单
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
    
    clear 2>/dev/null || echo ""
    echo "========================================"
    echo "      CF Server Monitor - 音量键控制"
    echo "========================================"
    echo ""
    echo "  音量+ : 切换选项    音量- : 确认选择"
    echo ""
    echo "----------------------------------------"
    
    for i in "${!options[@]}"; do
        if [ $i -eq $selected ]; then
            echo "  ${GREEN}▶ $((i+1)). ${options[$i]}${NC}"
        else
            echo "    $((i+1)). ${options[$i]}"
        fi
    done
    echo ""
    echo "----------------------------------------"
    echo "  当前选中: ${YELLOW}${options[$selected]}${NC}"
    echo "  按音量- 确认执行"
    echo "========================================"
}

# 确认对话框
confirm_action() {
    local action="$1"
    local confirm_count=0
    local max_confirm=3
    
    echo ""
    echo "========================================"
    echo "  ⚠️  确认执行: ${YELLOW}$action${NC}"
    echo "========================================"
    echo ""
    echo "  请再次按 音量- 确认执行"
    echo "  按 音量+ 取消"
    echo ""
    echo -n "  等待确认"
    
    while [ $confirm_count -lt 10 ]; do
        local event=$(read_key_event 0.3)
        local key=$(detect_volume_key "$event")
        
        case "$key" in
            down)
                echo ""
                echo "  ${GREEN}✅ 已确认，正在执行...${NC}"
                return 0
                ;;
            up)
                echo ""
                echo "  ${RED}❌ 已取消${NC}"
                return 1
                ;;
        esac
        
        confirm_count=$((confirm_count + 1))
        echo -n "."
        sleep 0.3
    done
    
    echo ""
    echo "  ${YELLOW}⏰ 操作超时，已取消${NC}"
    return 1
}

# 执行操作
execute_action() {
    local action_index=$1
    local action_name=""
    
    case $action_index in
        0) action_name="启动服务"; /system/bin/sh "$MANAGER" start ;;
        1) action_name="停止服务"; /system/bin/sh "$MANAGER" stop ;;
        2) action_name="重启服务"; /system/bin/sh "$MANAGER" restart ;;
        3) action_name="查看状态"; /system/bin/sh "$MANAGER" status ;;
        4) action_name="查看日志"; /system/bin/sh "$MANAGER" logs ;;
        5) action_name="查看版本"; /system/bin/sh "$MANAGER" version ;;
        6) action_name="退出"; exit 0 ;;
    esac
    
    echo ""
    echo "========================================"
    echo "  执行结果："
    echo "========================================"
    echo ""
}

# 主循环
main_loop() {
    local selected=0
    local total_options=7
    
    # 清空输入缓冲区
    dd if="$INPUT_DEVICE" bs=24 count=10 2>/dev/null
    
    while true; do
        show_menu $selected
        
        # 等待按键
        local event=$(read_key_event 0.5)
        local key=$(detect_volume_key "$event")
        
        case "$key" in
            up)
                # 音量+ 向上切换
                selected=$((selected - 1))
                if [ $selected -lt 0 ]; then
                    selected=$((total_options - 1))
                fi
                ;;
            down)
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
                
                # 二次确认
                if confirm_action "$action_name"; then
                    execute_action $selected
                    if [ $selected -ne 6 ]; then
                        echo ""
                        echo "  按任意音量键继续..."
                        read_key_event 2 > /dev/null
                    else
                        exit 0
                    fi
                else
                    echo ""
                    echo "  按任意音量键继续..."
                    read_key_event 2 > /dev/null
                fi
                ;;
            both)
                # 同时按两个键 - 快速退出
                echo ""
                echo "  ${RED}强制退出${NC}"
                exit 0
                ;;
        esac
    done
}

# 检查manager.sh是否存在
if [ ! -f "$MANAGER" ]; then
    echo "错误: manager.sh 不存在于 $MANAGER"
    exit 1
fi

# 检查input设备
if [ ! -e "$INPUT_DEVICE" ]; then
    echo "警告: 找不到输入设备 $INPUT_DEVICE"
    echo "尝试使用备用方案..."
    # 可以在这里添加备用方案，比如使用/proc或/sys接口
fi

# 主入口
case "$1" in
    menu|"")
        main_loop
        ;;
    start|1)
        /system/bin/sh "$MANAGER" start
        ;;
    stop|2)
        /system/bin/sh "$MANAGER" stop
        ;;
    restart|3)
        /system/bin/sh "$MANAGER" restart
        ;;
    status|4)
        /system/bin/sh "$MANAGER" status
        ;;
    logs|5)
        /system/bin/sh "$MANAGER" logs
        ;;
    version|6)
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