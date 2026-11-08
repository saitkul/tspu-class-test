cat > /tmp/class_runner.sh <<'EOF'
S=$1
DOM=${2:-www.youtube.com}
REP=${3:-3}
TMO=${4:-2.5}
L=/tmp/class_test.log
A=/tmp/class_report.awk
R=/tmp/class_report.txt

[ -f "$S" ] || { echo "Не найден файл со списком: $S"; exit 1; }
# blockcheck2.sh запускается после cd в /opt/zapret2, поэтому путь должен быть абсолютным
S=$(readlink -f "$S") || { echo "Не удалось определить полный путь к списку: $S"; exit 1; }

[ -f /opt/zapret2/blockcheck2.sh ] || { echo "Не найден /opt/zapret2/blockcheck2.sh: Zapret2 не установлен?"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Не найден curl: blockcheck2 без него не работает."; exit 1; }
nslookup "$DOM" >/dev/null 2>&1 || echo "ВНИМАНИЕ: $DOM не резолвится. Проверьте DNS и отключите VPN, иначе результат теста будет неверным."

cat > $A <<'AWK'
function norm(x) { gsub(/\r/, "", x); gsub(/[ \t]+/, " ", x); sub(/^ /, "", x); sub(/ $/, "", x); return x }
NR==FNR { x = norm($0); if (x != "" && substr(x, 1, 1) != "#") { n++; lst[n] = x } next }
/^- curl_test_https_tls1[23] ipv4 / {
  cur = ""
  i = index($0, " : nfqws2 ")
  if (i > 0) {
    head = substr($0, 1, i - 1); s = norm(substr($0, i + 10))
    sub(/^- curl_test_https_/, "", head); split(head, h, " "); p = h[1]
    for (k = 1; k <= n; k++) if (lst[k] == s) { cur = k; key = p SUBSEP k; tot[key] = 0; ok[key] = 0; part[key] = 0; seen = 1 }
  }
  next
}
/^\* / || /^clearing/ || /^!!!!! curl/ { cur = ""; next }
# При одном повторе blockcheck2 не печатает строки "[attempt N]", только итог по стратегии.
rep == 1 && /^curl: / {
  if (cur != "" && match($0, /with [0-9]+ bytes received/)) { b = substr($0, RSTART + 5, RLENGTH - 20) + 0; if (b > 0) part[key] = 1 }
  next
}
rep == 1 && /^!!!!! AVAILABLE !!!!!/ { if (cur != "") { tot[key] = 1; ok[key] = 1 } next }
rep == 1 && /^UNAVAILABLE/ { if (cur != "") tot[key] = 1; next }
/^\[attempt [0-9]+\]/ {
  if (cur != "") {
    tot[key]++
    if ($0 ~ /AVAILABLE/) ok[key]++
    else if (match($0, /with [0-9]+ bytes received/)) { b = substr($0, RSTART + 5, RLENGTH - 20) + 0; if (b > 0) part[key]++ }
  }
  next
}
END {
  if (!seen) { print "ВНИМАНИЕ: в логе нет строк из вашего списка. Пришлите краткий лог."; exit }
  np = split("tls12 tls13", P, " "); slowany = 0
  for (q = 1; q <= np; q++) {
    p = P[q]; st = ""; fl = ""; sl = ""; det = ""
    for (k = 1; k <= n; k++) {
      key = p SUBSEP k
      if (key in tot && tot[key] > 0) {
        det = det sprintf(" %d:%d/%d%s", k, ok[key], tot[key], (part[key] > 0 ? "~" part[key] : ""))
        if (ok[key] == tot[key]) st = st " " k
        else if (ok[key] > 0) fl = fl " " k
        else if (part[key] > 0) { sl = sl " " k; slowany = 1 }
      }
    }
    printf "%s стабильно:%s | нестабильно:%s | медленно:%s\n", p, (st == "" ? " нет" : st), (fl == "" ? " нет" : fl), (sl == "" ? " нет" : sl)
    printf "   попытки (строка:успешных/всего, ~N = N попыток, где данные пошли, но не успели загрузиться):%s\n", det
    S[p] = st; F[p] = fl; M[p] = sl; D[p] = det
  }
  if (rpt != "") {
    split("TLS 1.2|TLS 1.3", LBL, "|")
    for (q = 1; q <= np; q++) {
      p = P[q]
      printf "%s: стабильно:%s | нестабильно:%s | медленно:%s\n", LBL[q], (S[p] == "" ? " нет" : S[p]), (F[p] == "" ? " нет" : F[p]), (M[p] == "" ? " нет" : M[p]) > rpt
    }
    for (q = 1; q <= np; q++) printf "Попытки %s (строка:успешных/всего):%s\n", LBL[q], D[P[q]] > rpt
    print "Рабочие стратегии (прошли все попытки):" > rpt
    any = 0
    for (k = 1; k <= n; k++) {
      a = index(S["tls12"] " ", " " k " ") > 0; b = index(S["tls13"] " ", " " k " ") > 0
      if (a || b) { printf "%d [%s]: %s\n", k, (a && b ? "TLS 1.2 и 1.3" : (a ? "только TLS 1.2" : "только TLS 1.3")), lst[k] > rpt; any = 1 }
    }
    if (!any) print "нет" > rpt
    close(rpt)
  }
  if (slowany) print "ПОДСКАЗКА: у строк «медленно» соединение установилось и данные пошли, но не успели загрузиться за отведённое время. Это не блокировка. Повторите с большим временем ожидания, например: sh /tmp/class_runner.sh СПИСОК www.youtube.com 3 8"
}
AWK

WAS=0
pgrep nfqws2 >/dev/null 2>&1 && WAS=1
CLEANED=0
BPID=

cleanup() {
  [ "$CLEANED" = 1 ] && return
  CLEANED=1
  if [ -n "$BPID" ] && kill -0 "$BPID" 2>/dev/null; then
    kill "$BPID" 2>/dev/null
    wait "$BPID" 2>/dev/null
  fi
  echo
  if [ "$WAS" = 1 ]; then
    if /etc/init.d/zapret2 start >/dev/null 2>&1; then
      echo "Zapret2 снова запущен."
    else
      echo "ВНИМАНИЕ: не удалось запустить Zapret2. Выполните вручную: /etc/init.d/zapret2 start"
    fi
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

[ "$WAS" = 1 ] && /etc/init.d/zapret2 stop >/dev/null 2>&1
cd /opt/zapret2 || exit 1
echo "В данный момент производится тестирование сети, пожалуйста подождите (обычно несколько минут)..."
BATCH=1 TEST=custom LIST_HTTPS_TLS12=$S LIST_HTTPS_TLS13=$S DOMAINS=$DOM IPVS=4 ENABLE_HTTP=0 ENABLE_HTTPS_TLS12=1 ENABLE_HTTPS_TLS13=1 ENABLE_HTTP3=0 REPEATS=$REP CURL_HTTPS_GET=1 CURL_MAX_TIME=$TMO ./blockcheck2.sh > $L 2>&1 &
BPID=$!
TOTAL=$(( $(grep -cvE '^[[:space:]]*(#|$)' "$S") * 2 ))
T0=$(date +%s)
while kill -0 "$BPID" 2>/dev/null; do
  DONE=$(grep -c '^- curl_test_https_tls1[23] .* : nfqws2 ' $L 2>/dev/null)
  [ "$DONE" -gt "$TOTAL" ] && DONE=$TOTAL
  EL=$(( $(date +%s) - T0 ))
  if [ "$DONE" -gt 0 ]; then
    printf '\r  Проверка стратегий: %s из %s, прошло %s:%02d. Не закрывайте терминал.   ' "$DONE" "$TOTAL" $((EL / 60)) $((EL % 60))
  else
    printf '\r  Подготовка к тесту, прошло %s:%02d. Не закрывайте терминал.   ' $((EL / 60)) $((EL % 60))
  fi
  sleep 2
done
wait "$BPID" 2>/dev/null
printf '\r%-78s\r' ""

sed -e '/^More details here:/d' -e '/^curl failed to verify/d' -e '/^establish a secure connection/d' -e '/^how to fix it/d' -e '/^$/d' $L > $L.short

NB12=0; NB13=0
grep -q "curl_test_https_tls12 .*working without bypass" $L && NB12=1
grep -q "curl_test_https_tls13 .*working without bypass" $L && NB13=1

rm -f $R
echo
echo "=== ИТОГ ($DOM, список: $S, повторов: $REP, ожидание: $TMO с) ==="
if [ $NB12 = 1 ] && [ $NB13 = 1 ]; then
  echo "Результат: $DOM открывается без обхода, стратегии не проверялись." > $R
  echo "ОБХОД НЕ ТРЕБУЕТСЯ: $DOM открывается без обхода, стратегии не проверялись."
  echo "Это не значит, что «ничего не прошло». Если видео всё же тормозит или не грузится,"
  echo "повторите тест на узле видео: sh /tmp/class_runner.sh $S rr1---sn-ИМЯ.googlevideo.com $REP"
  echo "(имя узла: F12 -> Network -> фильтр googlevideo в браузере)."
elif ! grep -q "^\* SUMMARY" $L; then
  echo "Результат: тест не завершился (в логе нет блока SUMMARY)." > $R
  echo "ТЕСТ НЕ ЗАВЕРШИЛСЯ (в логе нет блока SUMMARY). Пришлите краткий лог."
else
  awk -v rep="$REP" -v rpt="$R" -f $A $S $L
  [ -s $R ] || echo "Результат: в логе нет строк из списка." > $R
  if [ $NB12 = 1 ]; then
    echo "TLS 1.2: открывается без обхода, стратегии для него не проверялись."
    echo "TLS 1.2: открывается без обхода, стратегии не проверялись." >> $R
  fi
  if [ $NB13 = 1 ]; then
    echo "TLS 1.3: открывается без обхода, стратегии для него не проверялись."
    echo "TLS 1.3: открывается без обхода, стратегии не проверялись." >> $R
  fi
fi

MODEL=$(cat /tmp/sysinfo/model 2>/dev/null)
FW=$(. /etc/openwrt_release 2>/dev/null && echo "$DISTRIB_DESCRIPTION ($DISTRIB_ARCH)")
echo
echo "=== ОТЧЁТ ДЛЯ issue #1 (скопируйте всё между этими строками) ==="
echo "Роутер: ${MODEL:-неизвестно}"
echo "Прошивка: ${FW:-неизвестно}"
echo "Тест: $DOM, повторов $REP, ожидание $TMO с, IPv4"
cat $R
echo "=== конец отчёта ==="
echo
echo "Краткий лог: $L.short"
echo "Полный лог: $L"
EOF

cat > /tmp/list_stage1.txt <<'EOF'
--payload=tls_client_hello --lua-desync=multidisorder:pos=midsld
--payload=tls_client_hello --lua-desync=multisplit:pos=midsld
--payload=tls_client_hello --lua-desync=multidisorder:pos=sld
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:ip_autottl=-2,3-20:repeats=6
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=6 --lua-desync=multisplit:pos=midsld
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=6 --lua-desync=multidisorder:pos=midsld
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_md5
--payload=tls_client_hello --lua-desync=rst:ip_autottl=-2,3-20
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=6
EOF

sh /tmp/class_runner.sh /tmp/list_stage1.txt www.youtube.com 3
