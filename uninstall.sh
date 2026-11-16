#!/bin/sh
# ============================================================
#  luci-app-tspu-test - полное удаление (в т.ч. после install.sh)
#  Останавливает идущий тест (Zapret2 возвращается), снимает пакет
#  и чистит временные файлы.
# ============================================================
[ "$(id -u)" = "0" ] || { echo "Запустите от root"; exit 1; }

# Остановить идущий тест и вернуть Zapret2
[ -x /usr/bin/tspu-test ] && /usr/bin/tspu-test stop >/dev/null 2>&1

# Снять пакет через менеджер, если он был установлен им
if command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -q luci-app-tspu-test; then
    opkg remove luci-app-tspu-test
elif command -v apk >/dev/null 2>&1 && apk list --installed 2>/dev/null | grep -q luci-app-tspu-test; then
    apk del luci-app-tspu-test
fi

# Файлы приложения (на случай ручной установки)
rm -f /usr/bin/tspu-test
rm -f /usr/share/luci/menu.d/luci-app-tspu-test.json
rm -f /usr/share/rpcd/acl.d/luci-app-tspu-test.json
rm -f /usr/lib/lua/luci/controller/tspu-test.lua
rm -rf /usr/lib/lua/luci/view/tspu-test
rm -f /www/luci-static/resources/view/tspu-test/test.js 2>/dev/null
rm -rf /usr/share/luci/htdocs/luci-static/resources/view/tspu-test 2>/dev/null

# Временные файлы теста
rm -f /tmp/tspu_test.pid /tmp/tspu_test.status /tmp/tspu_test_run.log
rm -f /tmp/class_test.log /tmp/class_test.log.short
rm -f /tmp/class_report.awk /tmp/class_report.txt /tmp/list_stage1.txt /tmp/class_runner.sh
rm -f /tmp/tspu_domains.txt

/etc/init.d/rpcd reload 2>/dev/null

echo "luci-app-tspu-test удалён. Файлы Zapret2 и ZeroBlock не затронуты."
