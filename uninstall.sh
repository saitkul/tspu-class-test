#!/bin/sh
# ============================================================
#  luci-app-tspu-test - полное удаление (в т.ч. после install.sh)
# ============================================================
[ "$(id -u)" = "0" ] || { echo "Запустите от root"; exit 1; }

# Остановить идущий тест и вернуть Zapret2
[ -x /usr/bin/tspu-test ] && /usr/bin/tspu-test stop >/dev/null 2>&1

rm -f /usr/bin/tspu-test
rm -f /usr/share/luci/menu.d/luci-app-tspu-test.json
rm -f /usr/share/rpcd/acl.d/luci-app-tspu-test.json
rm -f /usr/lib/lua/luci/controller/tspu-test.lua
rm -rf /usr/lib/lua/luci/view/tspu-test

# Подчистить временные файлы теста
rm -f /tmp/tspu_test.pid /tmp/tspu_test.status /tmp/tspu_test_run.log
rm -f /tmp/class_test.log /tmp/class_test.log.short
rm -f /tmp/class_report.awk /tmp/class_report.txt /tmp/list_stage1.txt /tmp/class_runner.sh

[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >/dev/null 2>&1

echo "luci-app-tspu-test удалён. Файлы Zapret2 и ZeroBlock не затронуты."
