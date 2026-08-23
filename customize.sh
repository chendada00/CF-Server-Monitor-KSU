#!/system/bin/sh

ui_print "- Installing CF Server Monitor"

# KernelSU 安装模块后会处理默认权限，
# 这里明确设置我们需要执行的文件权限。

set_perm "$MODPATH/boot-completed.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

set_perm "$MODPATH/scripts/manager.sh" 0 0 0755
set_perm "$MODPATH/scripts/save-config.sh" 0 0 0755

set_perm "$MODPATH/bin/cf-probe" 0 0 0755

ui_print "- CF Server Monitor installed"