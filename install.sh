#!/bin/sh
# ============================================================
#  luci-app-tspu-test - установка на OpenWrt 23.05/24.x (opkg)
#  и 25.x (apk). Скрипт сам определяет менеджер пакетов и ищет
#  подходящий пакет в своей папке или в /tmp.
#
#  Использование: положите рядом install.sh и пакет (.ipk или .apk),
#  затем:  sh install.sh
#  Без пакета скрипт скачает его из GitHub Releases (нужен интернет).
# ============================================================
[ "$(id -u)" = "0" ] || { echo "Запустите от root"; exit 1; }

REPO="https://github.com/saitkul/tspu-class-test/releases/latest/download"
PKG="luci-app-tspu-test"

# --- 1. Определить менеджер пакетов (command -v даёт полный путь) ---
PKG_MGR=""
if command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
fi

# --- 2. Найти пакет: локально рядом или в /tmp (формат под менеджер приоритетнее) ---
find_pkg() {
    if [ "$PKG_MGR" = "apk" ]; then
        for f in "$DIR"/*.apk /tmp/$PKG*.apk "$DIR"/*all.ipk /tmp/$PKG*.ipk; do
            [ -f "$f" ] && { echo "$f"; return 0; }
        done
    else
        for f in "$DIR"/*all.ipk /tmp/$PKG*.ipk "$DIR"/*.apk /tmp/$PKG*.apk; do
            [ -f "$f" ] && { echo "$f"; return 0; }
        done
    fi
    return 1
}

DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PKG_FILE=$(find_pkg)

if [ -z "$PKG_FILE" ]; then
    VER=$(command -v curl >/dev/null 2>&1 && \
          curl -sL -o /dev/null -w '%{url_effective}' "$REPO" | sed 's|.*/||' || echo "")
    [ -z "$VER" ] && VER="$PKG"
    EXT="ipk"; [ "$PKG_MGR" = "apk" ] && EXT="apk"
    echo "Пакета рядом нет. Скачиваю $PKG.$EXT из Releases..."
    curl -sL -o "/tmp/$PKG.$EXT" "$REPO/$PKG.$EXT" || { echo "Скачивание не удалось"; exit 1; }
    PKG_FILE="/tmp/$PKG.$EXT"
fi

# --- 3. Установка ---
case "$PKG_MGR" in
    opkg)
        opkg install --force-reinstall "$PKG_FILE"
        ;;
    apk)
        apk add --allow-untrusted --force-reinstall "$PKG_FILE"
        ;;
    *)
        echo "Не найден ни opkg, ни apk. Установите пакет вручную:" >&2
        echo "  opkg install /tmp/$PKG.ipk     (OpenWrt 23.05/24.x)" >&2
        echo "  apk add --allow-untrusted /tmp/$PKG.apk   (OpenWrt 25.x)" >&2
        exit 1
        ;;
esac

# --- 4. Сброс кэша LuCI, перечитание ACL и ГАРАНТИРОВАННАЯ деавторизация ---
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache/ 2>/dev/null
/etc/init.d/rpcd reload 2>/dev/null
# уничтожить ВСЕ сессии LuCI через ubus (как выход из LuCI): мгновенно и
# синхронно, без рестарта rpcd и без гонки с логином - панель сразу просит свежий вход
ok=0
for sid in $(ubus call session list 2>/dev/null | grep -oE '"[^"]+"' | tr -d '"'); do
	ubus call session destroy '{"ubus_rpc_session":"'"$sid"'"}' >/dev/null 2>&1 && ok=1
done
[ "$ok" = "1" ] || /etc/init.d/rpcd restart 2>/dev/null

echo
echo "Установлено. Сессии панели LuCI завершены - войдите заново"
echo "(обязательная деавторизация после установки luci-приложения)."
echo "После входа: LuCI -> Службы -> TSPU test."
echo "Требуется установленный Zapret2 в /opt/zapret2 (с blockcheck2.sh) и curl."
