#!/bin/sh
# ============================================================
#  luci-app-tspu-test - универсальная установка (OpenWrt 23.05/24.10/25.x)
#  Использование: положите рядом install.sh и data.zip (или распакованную
#  папку data/), затем:  sh install.sh
# ============================================================
set -e

DIR=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = "0" ] || { echo "Запустите от root"; exit 1; }

if [ ! -d "$DIR/data" ]; then
  echo "Распаковываю data.zip..."
  command -v unzip >/dev/null 2>&1 && unzip -o "$DIR/data.zip" -d "$DIR" || {
    echo "unzip не найден: выполните на ПК: data.zip -> data/ рядом с install.sh"; exit 1; }
fi

[ -d "$DIR/data" ] || { echo "Не найдена папка data/"; exit 1; }

echo "Копирую файлы..."
cp -r "$DIR/data/." / 2>/dev/null || {
  mkdir -p /usr/bin /usr/share/luci/menu.d /usr/share/rpcd/acl.d \
           /usr/lib/lua/luci/controller /usr/lib/lua/luci/view/tspu-test
  cp "$DIR/data/usr/bin/tspu-test" /usr/bin/tspu-test
  cp "$DIR/data/usr/share/luci/menu.d/luci-app-tspu-test.json" /usr/share/luci/menu.d/luci-app-tspu-test.json
  cp "$DIR/data/usr/share/rpcd/acl.d/luci-app-tspu-test.json" /usr/share/rpcd/acl.d/luci-app-tspu-test.json
  cp "$DIR/data/usr/lib/lua/luci/controller/tspu-test.lua" /usr/lib/lua/luci/controller/tspu-test.lua
  cp "$DIR/data/usr/lib/lua/luci/view/tspu-test/test.htm" /usr/lib/lua/luci/view/tspu-test/test.htm
}
chmod 755 /usr/bin/tspu-test
chmod 644 /usr/share/luci/menu.d/luci-app-tspu-test.json /usr/share/rpcd/acl.d/luci-app-tspu-test.json
chmod 644 /usr/lib/lua/luci/controller/tspu-test.lua /usr/lib/lua/luci/view/tspu-test/test.htm

[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd restart >/dev/null 2>&1

echo
echo "Установлено. Откройте LuCI -> Службы -> TSPU test."
echo "Если пункта нет - перелогиньтесь в LuCI или обновите страницу (Ctrl+F5)."
echo "Требуется установленный Zapret2 в /opt/zapret2 и curl."
