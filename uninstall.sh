#!/bin/sh
# ============================================================
#  luci-app-tspu-test - полное удаление (в т.ч. после install.sh)
#  Останавливает идущий тест (Zapret2 возвращается), снимает пакет
#  и чистит временные файлы.
# ============================================================
[ "$(id -u)" = "0" ] || { echo "Запустите от root"; exit 1; }

# Остановить ВСЕ фоновые инструменты приложения (ревью 3.3.0: uninstall
# оставлял живыми канарейку/прод/валидатор/ytbest и ytsniff)
[ -x /usr/bin/tspu-test ] && /usr/bin/tspu-test stop >/dev/null 2>&1
[ -x /usr/bin/tspu-test ] && /usr/bin/tspu-test validate stop >/dev/null 2>&1
[ -x /usr/bin/tspu-test ] && /usr/bin/tspu-test prod stop >/dev/null 2>&1
[ -x /usr/bin/tspu-test ] && /usr/bin/tspu-test canary stop >/dev/null 2>&1
[ -x /usr/bin/tspu-test ] && /usr/bin/tspu-test yt stop >/dev/null 2>&1
pkill -f '[y]tsniff' 2>/dev/null
pkill -f '[b]lockcheck2.sh' 2>/dev/null
# Вернуть Zapret2, если его остановил НАШ инструмент (флаг .was от Теста/
# Валидатора/Подбора); если Zapret2 был выключен пользователем до нас —
# не трогаем, печатаем подсказку
if ! pgrep nfqws2 >/dev/null 2>&1; then
    if [ -f /tmp/tspu_test.was ]; then
        /etc/init.d/zapret2 start >/dev/null 2>&1
        echo "Zapret2 возвращён (был остановлен нашим инструментом)."
    else
        echo "Zapret2 не запущен (так и было). Запуск вручную: /etc/init.d/zapret2 start"
    fi
fi
# Снять GGC-ремап: uci-записи address с нашими семействами googlevideo
for A in $(uci -q get dhcp.@dnsmasq[0].address 2>/dev/null); do
    case "$A" in *googlevideo.com*) uci -q del_list dhcp.@dnsmasq[0].address="$A" ;; esac
done
uci -q commit dhcp 2>/dev/null
/etc/init.d/dnsmasq restart >/dev/null 2>&1

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
rm -f /tmp/tspu_test.pid /tmp/tspu_test.status /tmp/tspu_test_run.log /tmp/tspu_test.was
rm -f /tmp/class_test.log /tmp/class_test.log.short
rm -f /tmp/class_report.awk /tmp/class_report.txt /tmp/class_report.d* /tmp/list_stage1.txt /tmp/class_runner.sh
rm -f /tmp/tspu_domains.txt /tmp/class_normlist.* /tmp/class_minilist.* /tmp/tspu_curl_probe /tmp/tspu_curl_metrics.*
rm -f /tmp/tspu_val.pid /tmp/tspu_val.status /tmp/tspu_val.log /tmp/tspu_val.report /tmp/tspu_val_run.log /tmp/tspu_validate.txt /tmp/tspu_validate_norm.txt
rm -f /tmp/tspu_prod.pid /tmp/tspu_prod.status /tmp/tspu_prod.log /tmp/tspu_prod_run.log /tmp/tspu_prod.stop
rm -f /tmp/tspu_can.pid /tmp/tspu_can.status /tmp/tspu_canary.log /tmp/tspu_can_run.log /tmp/tspu_can.stop
rm -f /tmp/tspu_yt.log /tmp/tspu_ytn.log /tmp/tspu_ytn.start /tmp/tspu_yt.mode /tmp/tspu_yt.start /tmp/tspu_yt.sec /tmp/tspu_yt.exit
rm -rf /tmp/ytbest
rm -f /tmp/tspu_transport.txt /tmp/tspu_apply.log /tmp/tspu_profiles.log /tmp/tspu_utls.log
rm -f /tmp/tspu_apply.script /tmp/tspu_apply.hostlist /tmp/tspu_apply.l3 /tmp/tspu_ggc_remap.conf
rm -rf /usr/share/tspu-test/ytbest

/etc/init.d/rpcd reload 2>/dev/null

echo "luci-app-tspu-test удалён. Файлы Zapret2 и ZeroBlock не затронуты."
