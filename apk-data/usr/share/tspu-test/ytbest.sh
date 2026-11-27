#!/bin/sh
# ytbest — автоматический подбор блока circular для Zapret2 (YouTube / googlevideo)
# Прогоняет список стратегий-кандидатов на нескольких узлах googlevideo через
# blockcheck2 (как TSPU test), считает попытки по каждой версии TLS, отдельно —
# с отпечатком браузера (utlscurl, uTLS Chrome), отбрасывает «мягкие» узлы и
# нерабочие строки и собирает готовый блок circular. Конфиг Zapret2 НЕ меняет.
#
#   ytbest.sh start [-r ПОВТОРЫ] [-m both|curl|browser] [-n СТУПЕНЕЙ] [узел ...]
#   ytbest.sh status | stop | report | block
#
# Узлы: аргументами или файлом /root/ytbest/nodes.txt (по одному в строке).
# Кандидаты: /root/ytbest/candidates.txt (одна стратегия на строку, # — комментарий).
# Итог: /root/ytbest/last_report.txt и /root/ytbest/last_block.txt (переживают перезагрузку).

VER=1.1.2
# Пакетная версия (TSPU test): база — в /usr/share/tspu-test/ytbest (переживает перезагрузку),
# бинари — в /usr/bin. Переопределяется переменными YTB_BASE/YTB_UTLS/YTB_SNIFF.
BASE=${YTB_BASE:-/usr/share/tspu-test/ytbest}
RUN=${YTB_RUN:-/tmp/ytbest}
PIDF=$RUN/pid
STATUS=$RUN/status
FLAG=$RUN/zapret2.was
UTLS=${YTB_UTLS:-/usr/bin/utlscurl}
SNIFF=${YTB_SNIFF:-/usr/bin/ytsniff}
ZDIR=${YTB_ZDIR:-/opt/zapret2}
BC=$ZDIR/blockcheck2.sh
ZINIT=${YTB_INIT:-/etc/init.d/zapret2}

mkdir -p "$RUN" "$BASE"

alive() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; }

usage() {
	cat <<EOF
ytbest $VER — подбор блока circular для YouTube (Zapret2)
  ytbest.sh start [-r 5] [-m both|curl|browser] [-n 6] [узел ...]
  ytbest.sh status   — ход работы
  ytbest.sh stop     — остановить (Zapret2 будет запущен обратно)
  ytbest.sh report   — последний отчёт
  ytbest.sh block    — только готовый блок
  ytbest.sh selftest — проверка установки
  ytbest.sh nodes [сек]        — сам найти узлы googlevideo: слушает, куда ходит YouTube
                                 (смотрите YouTube на ПК/айфоне), пишет nodes.txt
  ytbest.sh auto [сек] [ключи start] — nodes, затем сразу start по найденным узлам
Узлы — конкретные rrN---sn-....googlevideo.com (из IPvFoo / DevTools).
EOF
}

# ---------------------------------------------------------------- поиск узлов
# Адреса Google (собственные узлы googlevideo). Всё остальное с именем
# *.googlevideo.com — кэш провайдера (Google Global Cache): его не тестируем.
is_google_awk='function google(ip) { return ip ~ /^(74\.125|173\.194|209\.85|142\.25[01]|172\.217|172\.253|216\.58|216\.239|108\.177|64\.233|66\.102|66\.249|72\.14|192\.178)\./ || ip ~ /^(2a00:1450|2607:f8b0|2404:6800|2800:3f0):/ }'

do_nodes() {
	SEC=${1:-180}
	case "$SEC" in ''|*[!0-9]*) echo "Время — число секунд 30..900"; return 1 ;; esac
	[ "$SEC" -ge 30 ] && [ "$SEC" -le 900 ] || { echo "Время — число секунд 30..900"; return 1; }
	[ -x "$SNIFF" ] || { echo "Нет $SNIFF"; return 1; }
	pgrep nfqws2 >/dev/null 2>&1 || echo "ВНИМАНИЕ: Zapret2 не запущен — YouTube может не грузиться, узлов будет мало."
	echo "Слушаю $SEC с. Сейчас смотрите YouTube на ПК и айфоне: несколько разных видео, 4K, шортсы."
	echo "(ничего не меняется — только читаются имена серверов из начала соединений)"
	"$SNIFF" -i br-lan,tailscale0 -t "$SEC" -f googlevideo.com > "$RUN/sniff.tsv" 2> "$RUN/sniff.err"
	R=$?
	[ "$R" = 0 ] || { echo "Ошибка ytsniff: $(head -2 "$RUN/sniff.err")"; return 1; }
	if [ ! -s "$RUN/sniff.tsv" ]; then
		echo "Узлов googlevideo не замечено. Смотрели YouTube во время записи? Повторите: ytbest nodes"
		return 1
	fi
	echo
	echo "Соединений  Узел                                        Адрес              Чей"
	awk -F'\t' "$is_google_awk"'
		{ split($3, ips, ","); g = google(ips[1]) ? "Google" : "кэш провайдера (не тестируем)"
		  printf "%-11s %-43s %-18s %s\n", $1, $2, ips[1], g }' "$RUN/sniff.tsv"
	# один узел = одна часть sn-...: rr2---sn-x и rr4---sn-x — тот же сервер. Складываем
	# соединения по узлу, берём 4 разных узла Google; имя — самое нагруженное из rrN.
	# redirector.googlevideo.com и прочие не-rr имена — не видеоузлы, пропускаем.
	awk -F'\t' "$is_google_awk"'
		{ split($3, ips, ","); if (!google(ips[1])) next
		  h = $2; if (h !~ /^rr?[0-9]+---sn-/) next
		  sn = h; sub(/^rr?[0-9]+---/, "", sn)
		  tot[sn] += $1; if ($1 > best[sn]) { best[sn] = $1; name[sn] = h } }
		END { for (sn in tot) print tot[sn] "\t" name[sn] }' "$RUN/sniff.tsv" | sort -rn | head -4 | cut -f2 > "$RUN/nodes.new"
	if [ ! -s "$RUN/nodes.new" ]; then
		echo
		echo "Все замеченные узлы — кэш провайдера. Его тестировать не нужно; nodes.txt не изменён."
		return 1
	fi
	[ -f "$BASE/nodes.txt" ] && cp "$BASE/nodes.txt" "$BASE/nodes.prev.txt"
	{ echo "# найдено ytbest nodes $(date '+%d.%m.%Y %H:%M'), по числу соединений"; cat "$RUN/nodes.new"; } > "$BASE/nodes.txt"
	echo
	echo "В $BASE/nodes.txt записаны самые нагруженные узлы Google (разные sn-…) ($(wc -l < "$RUN/nodes.new") шт.; старый список — nodes.prev.txt):"
	sed 's/^/  /' "$RUN/nodes.new"
	return 0
}

# ---------------------------------------------------------------- проверки
busy_other() {
	pgrep -f '[t]spu-test _run' >/dev/null 2>&1 && { echo "идёт тест TSPU test"; return 0; }
	pgrep -f '[t]spu-test _validate' >/dev/null 2>&1 && { echo "идёт валидатор TSPU test"; return 0; }
	pgrep -f '[b]lockcheck2.sh' >/dev/null 2>&1 && { echo "уже работает blockcheck2"; return 0; }
	pgrep -f '[b]lockcheckw' >/dev/null 2>&1 && { echo "работает blockcheckw (bcw)"; return 0; }
	return 1
}

norm_candidates() {
	# $1 — исходный файл, $2 — результат. Одна стратегия на строку, CRLF и комментарии убраны.
	tr -d '\r' < "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -vE '^(#|$)' | tr -s ' ' | awk '!seen[$0]++' > "$2"
}

do_start() {
	REP=5; MODE=both; NR=6
	while [ $# -gt 0 ]; do
		case "$1" in
			-r) REP=$2; shift 2 ;;
			-m) MODE=$2; shift 2 ;;
			-n) NR=$2; shift 2 ;;
			-*) echo "Неизвестный ключ: $1"; usage; exit 1 ;;
			*) break ;;
		esac
	done
	case "$REP" in ''|*[!0-9]*) echo "Повторы — число 1..10"; exit 1 ;; esac
	[ "$REP" -ge 1 ] && [ "$REP" -le 10 ] || { echo "Повторы — число 1..10"; exit 1; }
	case "$NR" in ''|*[!0-9]*) echo "Ступеней — число 2..10"; exit 1 ;; esac
	[ "$NR" -ge 2 ] && [ "$NR" -le 10 ] || { echo "Ступеней — число 2..10"; exit 1; }
	case "$MODE" in both|curl|browser) ;; *) echo "Режим: both, curl или browser"; exit 1 ;; esac

	NODES="$*"
	[ -z "$NODES" ] && [ -s "$BASE/nodes.txt" ] && NODES=$(tr -d '\r' < "$BASE/nodes.txt" | grep -vE '^[[:space:]]*(#|$)' | tr '\n' ' ')
	[ -n "$NODES" ] || { echo "Нет узлов: укажите аргументами или в $BASE/nodes.txt"; exit 1; }
	for N in $NODES; do
		echo "$N" | grep -qE '^[A-Za-z0-9.-]+$' || { echo "Недопустимое имя узла: $N"; exit 1; }
		case "$N" in -*) echo "Недопустимое имя узла: $N"; exit 1 ;; esac
	done

	[ -f "$BC" ] || { echo "Не найден $BC (Zapret2 не установлен?)"; exit 1; }
	[ -s "$BASE/candidates.txt" ] || { echo "Нет файла кандидатов $BASE/candidates.txt"; exit 1; }
	if [ "$MODE" != curl ]; then
		[ -x "$UTLS" ] || { echo "Нет $UTLS (нужен для режима browser/both). Запустите с -m curl или положите файл."; exit 1; }
		"$UTLS" --version >/dev/null 2>&1 || { echo "$UTLS не запускается на этом роутере"; exit 1; }
	fi
	if alive; then echo "ytbest уже работает. Ход: ytbest.sh status"; exit 0; fi
	if W=$(busy_other); then echo "Сейчас нельзя: $W. Дождитесь окончания."; exit 1; fi

	norm_candidates "$BASE/candidates.txt" "$RUN/cand.txt"
	if grep -qE '[`$;&|<>\\]' "$RUN/cand.txt"; then
		echo "В кандидатах недопустимые символы (\` \$ ; & | < > \\)."; exit 1
	fi
	BAD=$(grep -vn '^--' "$RUN/cand.txt" | head -3)
	[ -z "$BAD" ] || { echo "Строки кандидатов должны начинаться с --payload=... / --lua-desync=...:"; echo "$BAD"; exit 1; }
	NC=$(wc -l < "$RUN/cand.txt")
	[ "$NC" -ge 1 ] || { echo "Кандидатов нет"; exit 1; }

	NN=$(echo $NODES | wc -w)
	PER=0
	[ "$MODE" != browser ] && PER=$((PER + NC * 2))
	[ "$MODE" != curl ] && PER=$((PER + NC))
	EST=$(( (PER * NN * REP * 15 / 10 + NN * 60) / 60 + 1 ))
	rm -f "$RUN"/log.* "$RUN/deleg.log" "$RUN/report.txt" "$RUN/block.txt"
	ZWAS=0; pgrep nfqws2 >/dev/null 2>&1 && ZWAS=1
	echo "state=starting" > "$STATUS"
	setsid /bin/sh "$0" _run "$REP" "$MODE" "$NR" "$EST" $NODES > "$RUN/run.log" 2>&1 < /dev/null &
	sleep 1
	echo "Запущено: узлов $NN, кандидатов $NC, повторов $REP, режим $MODE."
	echo "Примерно $EST мин. Всё это время Zapret2 ВЫКЛЮЧЕН (YouTube и Discord не работают)."
	echo "Можно закрыть терминал и выключить ПК; роутер НЕ перезагружать."
	[ "$ZWAS" = 1 ] || echo "Zapret2 сейчас уже выключен — после теста ytbest его НЕ включит (включите сами: /etc/init.d/zapret2 start)."
	echo "Ход: $0 status    Итог: $0 report"
}

# ---------------------------------------------------------------- фоновая часть
restore_zapret() {
	if [ -f "$FLAG" ]; then
		"$ZINIT" start >/dev/null 2>&1
		rm -f "$FLAG"
		echo "$(date '+%H:%M:%S') Zapret2 запущен обратно" >> "$RUN/run.log"
	fi
}

on_exit() {
	[ -n "$BPID" ] && kill "$BPID" 2>/dev/null
	pkill -f '[b]lockcheck2.sh' 2>/dev/null
	sleep 1
	# остатки правил blockcheck2 (если его прервали) — убрать
	nft list tables 2>/dev/null | grep -q 'inet zapret$' && nft delete table inet zapret 2>/dev/null
	restore_zapret
	rm -f "$PIDF"
}

do_run() {
	REP=$1; MODE=$2; NR=$3; EST=$4; shift 4
	NODES="$*"
	echo $$ > "$PIDF"
	BPID=""
	trap 'on_exit' EXIT
	trap 'echo "state=stopped" > "$STATUS"; exit 0' INT TERM
	T0=$(date +%s)
	echo "$(date '+%d.%m.%Y %H:%M:%S') старт: режим $MODE, повторов $REP, узлы: $NODES" > "$RUN/run.log"

	if pgrep nfqws2 >/dev/null 2>&1; then
		touch "$FLAG"
		"$ZINIT" stop >/dev/null 2>&1
		sleep 2
	fi

	MODES=""
	[ "$MODE" != curl ] && MODES="browser"
	[ "$MODE" != browser ] && MODES="$MODES curl"
	NC=$(wc -l < "$RUN/cand.txt")
	TOTAL=0
	for M in $MODES; do for N in $NODES; do
		if [ "$M" = browser ]; then TOTAL=$((TOTAL + NC)); else TOTAL=$((TOTAL + NC * 2)); fi
	done; done

	cd "$ZDIR" || exit 1
	for M in $MODES; do
		for N in $NODES; do
			LOG="$RUN/log.$M.$N"
			echo "$(date '+%H:%M:%S') $M $N" >> "$RUN/run.log"
			if [ "$M" = browser ]; then
				BATCH=1 SCANLEVEL=force TEST=custom LIST_HTTPS_TLS12="$RUN/cand.txt" LIST_HTTPS_TLS13="$RUN/cand.txt" \
				DOMAINS="$N" IPVS=4 ENABLE_HTTP=0 ENABLE_HTTPS_TLS12=0 ENABLE_HTTPS_TLS13=1 ENABLE_HTTP3=0 \
				REPEATS=$REP CURL_HTTPS_GET=1 CURL_MAX_TIME=2.5 CURL="$UTLS" UTLSCURL_LOG="$RUN/deleg.log" \
				./blockcheck2.sh > "$LOG" 2>&1 &
			else
				BATCH=1 SCANLEVEL=force TEST=custom LIST_HTTPS_TLS12="$RUN/cand.txt" LIST_HTTPS_TLS13="$RUN/cand.txt" \
				DOMAINS="$N" IPVS=4 ENABLE_HTTP=0 ENABLE_HTTPS_TLS12=1 ENABLE_HTTPS_TLS13=1 ENABLE_HTTP3=0 \
				REPEATS=$REP CURL_HTTPS_GET=1 CURL_MAX_TIME=2.5 \
				./blockcheck2.sh > "$LOG" 2>&1 &
			fi
			BPID=$!
			while kill -0 "$BPID" 2>/dev/null; do
				DONE=$(cat "$RUN"/log.* 2>/dev/null | grep -c '^- curl_test_https')
				echo "state=running cnt=$DONE total=$TOTAL mode=$M node=$N est_min=$EST started=$T0" > "$STATUS"
				sleep 5
			done
			wait "$BPID" 2>/dev/null
			BPID=""
		done
	done

	restore_zapret
	echo "state=analyzing" > "$STATUS"
	analyze "$REP" "$MODE" "$NR" "$T0" $NODES
	cp "$RUN/report.txt" "$BASE/last_report.txt" 2>/dev/null
	cp "$RUN/block.txt" "$BASE/last_block.txt" 2>/dev/null
	echo "state=done" > "$STATUS"
	echo "$(date '+%H:%M:%S') готово" >> "$RUN/run.log"
}

# ---------------------------------------------------------------- разбор и сборка
analyze() {
	REP=$1; MODE=$2; NR=$3; T0=$4; shift 4
	NODES="$*"
	DUR=$(( ($(date +%s) - T0) / 60 ))
	# 1) сырые счётчики: mode node tls line ok tot ; базовая линия: mode node tls 0 open
	: > "$RUN/counts.tsv"
	for F in "$RUN"/log.*; do
		[ -f "$F" ] || continue
		B=${F##*/log.}; M=${B%%.*}; N=${B#*.}
		awk -v M="$M" -v N="$N" -v CF="$RUN/cand.txt" '
			BEGIN { while ((getline l < CF) > 0) { nc++; idx[l] = nc } }
			/^- curl_test_https_tls1[23] / {
				t = ($0 ~ /tls13/) ? 13 : 12
				s = $0; sub(/^.*: nfqws2 /, "", s)
				if (s in idx) { cur = idx[s]; f = 1; seen[t, cur] = 1 } else f = 0
				base = 0; next
			}
			/^\* curl_test_https_tls12/ { tl = 12 }
			/^\* curl_test_https_tls13/ { tl = 13 }
			/^- checking without DPI bypass/ { base = 1; f = 0; next }
			/^- / || /^clearing/ || /^\* / { if (base && $0 !~ /^- checking/) base = 0; f = 0 }
			base && /^!!!!! AVAILABLE !!!!!/ { openb[tl] = 1; base = 0 }
			base && /^UNAVAILABLE/ { base = 0 }
			f && /^\[attempt [0-9]+\]/ { tot[t, cur]++; if ($0 ~ /AVAILABLE/) ok[t, cur]++ }
			f && /^!!!!! AVAILABLE !!!!!/ && !((t, cur) in tot) { tot[t, cur]++; ok[t, cur]++ }
			f && /^UNAVAILABLE/ && !((t, cur) in tot) { tot[t, cur]++ }
			END {
				for (k in seen) { split(k, a, SUBSEP); print M "\t" N "\t" a[1] "\t" a[2] "\t" ok[k] + 0 "\t" tot[k] + 0 }
				for (t in openb) print M "\t" N "\t" t "\t0\t1\t1"
			}' "$F" >> "$RUN/counts.tsv"
	done

	# 2) анализ: мягкие/открытые узлы, баллы, лесенка
	PRIM=browser; [ "$MODE" = curl ] && PRIM=curl
	DELEG=0; [ -s "$RUN/deleg.log" ] && DELEG=$(wc -l < "$RUN/deleg.log")
	awk -F'\t' -v PRIM="$PRIM" -v NR_MAX="$NR" -v CF="$RUN/cand.txt" -v REP="$REP" \
	    -v NODES="$NODES" -v MODE="$MODE" -v DUR="$DUR" -v DELEG="$DELEG" -v BLK="$RUN/block.txt" '
	BEGIN {
		while ((getline l < CF) > 0) { nc++; cand[nc] = l }
		nn = split(NODES, node, " ")
	}
	{ m = $1; n = $2; t = $3; i = $4; o = $5; tt = $6
	  if (i == 0) { open[m, n, t] = 1; next }
	  OK[m, n, t, i] = o; TOT[m, n, t, i] = tt; has[m] = 1 }
	END {
		print "=== ytbest: подбор блока circular для YouTube ==="
		print "Режим: " MODE "   повторов: " REP "   кандидатов: " nc "   длительность: " DUR " мин"
		print "Главная метрика: " (PRIM == "browser" ? "TLS 1.3 с отпечатком браузера (uTLS Chrome)" : "TLS 1.3 через curl")
		if (DELEG > 0) print "ВНИМАНИЕ: " DELEG " проверок браузерного режима ушли в обычный curl (неизвестные аргументы) - браузерные цифры неточны."
		print ""
		# классификация узлов по главной метрике (TLS 1.3)
		print "--- Узлы ---"
		nh = 0
		for (k = 1; k <= nn; k++) {
			n = node[k]; full = 0; any = 0
			for (i = 1; i <= nc; i++) if ((PRIM, n, 13, i) in TOT) { any++; if (TOT[PRIM, n, 13, i] > 0 && OK[PRIM, n, 13, i] == TOT[PRIM, n, 13, i]) full++ }
			cls = "трудный"
			if (any == 0) cls = "нет данных (узел не резолвится или скан прерван)"
			else if (open[PRIM, n, 13] || open["curl", n, 13]) cls = "открыт БЕЗ обхода (не фильтруется) - исключён"
			else if (full >= 0.5 * any) cls = "мягкий (" full " из " any " строк 100 %) - исключён"
			if (cls == "трудный") { nh++; hard[nh] = n }
			if (cls ~ /мягкий/) nsoft++
			print n ": " cls
		}
		print ""
		if (nh == 0) {
			print "Трудных узлов нет - выбирать не из чего. Возьмите узлы, на которых видео реально тормозит."
			exit
		}
		# баллы
		for (i = 1; i <= nc; i++) {
			P[i] = 0; C13[i] = 0; C12[i] = 0; PT[i] = 0
			for (h = 1; h <= nh; h++) {
				n = hard[h]
				P[i] += OK[PRIM, n, 13, i]; PT[i] += TOT[PRIM, n, 13, i]
				C13[i] += OK["curl", n, 13, i]; C12[i] += OK["curl", n, 12, i]
			}
			allok = 0
			for (k = 1; k <= nn; k++) for (mm in has) allok += OK[mm, node[k], 13, i] + OK[mm, node[k], 12, i]
			dead[i] = (allok == 0)
		}
		print "--- Кандидаты (успешных попыток на трудных узлах) ---"
		hdr = sprintf("%-3s %-9s", "N", (PRIM == "browser" ? "брауз1.3" : "curl1.3"))
		for (h = 1; h <= nh; h++) hdr = hdr sprintf(" %-6s", "у" h)
		if (has["curl"] && PRIM == "browser") hdr = hdr sprintf(" %-8s", "curl1.3")
		if (has["curl"]) hdr = hdr sprintf(" %-8s", "curl1.2")
		print hdr "  стратегия"
		# сортировка по P, затем C13, C12
		for (i = 1; i <= nc; i++) ord[i] = i
		for (a = 1; a <= nc; a++) for (b = a + 1; b <= nc; b++) {
			x = ord[a]; y = ord[b]
			if (P[y] > P[x] || (P[y] == P[x] && (C13[y] > C13[x] || (C13[y] == C13[x] && C12[y] > C12[x])))) { ord[a] = y; ord[b] = x }
		}
		for (a = 1; a <= nc; a++) {
			i = ord[a]
			line = sprintf("%-3d %-9s", i, P[i] "/" PT[i])
			for (h = 1; h <= nh; h++) line = line sprintf(" %-6s", OK[PRIM, hard[h], 13, i] + 0 "/" TOT[PRIM, hard[h], 13, i] + 0)
			if (has["curl"] && PRIM == "browser") line = line sprintf(" %-8s", C13[i])
			if (has["curl"]) line = line sprintf(" %-8s", C12[i])
			print line "  " cand[i] (dead[i] ? "   [0 везде" (nsoft ? ", даже на мягком узле: ТСПУ это отсекает или ваша версия Zapret2 это не поддерживает]" : "]") : "")
		}
		print ""
		for (h = 1; h <= nh; h++) print "у" h " = " hard[h]
		print ""
		# лесенка: жадное покрытие узлов
		maxP = 0; for (i = 1; i <= nc; i++) if (P[i] > maxP) maxP = P[i]
		if (maxP == 0) { print "Ни одна строка не прошла ни одной попытки на трудных узлах. Блок не собран."; exit }
		for (h = 1; h <= nh; h++) cov[h] = 0
		nr = 0
		while (nr < NR_MAX) {
			best = 0; bg = -1
			for (i = 1; i <= nc; i++) {
				if (used[i] || P[i] == 0) continue
				if (cand[i] !~ /--payload=tls_client_hello/ && cand[i] ~ /--payload=/) continue
				g = 0
				for (h = 1; h <= nh; h++) { v = OK[PRIM, hard[h], 13, i] - cov[h]; if (v > 0) g += v }
				sc = g * 100 + P[i] * 10 + C13[i] + C12[i] / 10
				if (nr > 0 && g == 0 && P[i] < 0.5 * maxP) continue
				if (sc > bg) { bg = sc; best = i }
			}
			if (!best) break
			nr++; rung[nr] = best; used[best] = 1
			for (h = 1; h <= nh; h++) if (OK[PRIM, hard[h], 13, best] > cov[h]) cov[h] = OK[PRIM, hard[h], 13, best]
		}
		print "--- Лесенка (порядок ступеней) ---"
		for (r = 1; r <= nr; r++) {
			i = rung[r]
			why = (r == 1) ? "лучшая в среднем" : "закрывает узлы, где слабее предыдущие"
			print r ". кандидат " i " (" P[i] "/" PT[i] ") - " why
		}
		print ""
		print "--- Готовый блок (вставить целиком вместо текущего) ---"
		out = "--out-range=-s34228\n--in-range=-s5556\n--lua-desync=circular:fails=2:time=60:retrans=3:nld=2:reset\n--in-range=x\n--payload=tls_client_hello"
		for (r = 1; r <= nr; r++) {
			nt = split(cand[rung[r]], tok, " ")
			for (k = 1; k <= nt; k++) if (tok[k] ~ /^--lua-desync=/) out = out "\n" tok[k] ":strategy=" r
		}
		print out
		print out > BLK
		print ""
		print "--- Что дальше ---"
		print "1. Сохраните текущий блок (он в Drive / в профиле Zapret2), вставьте новый, перезапустите Zapret2."
		print "2. Проверка ДОМА, не через Tailscale: 4K60 obSH5F2DYvk 5 мин (буфер, потери кадров) + айфон (авиарежим 5 с, минута)."
		print "3. Сравнение блоков при живом Zapret2 - TSPU test, вкладка «Прод-проба», 120 с на трудном узле (% успешных)."
		print "4. Узлы ведут себя по-разному: можно попробовать nld=3 вместо nld=2 в строке circular - у каждого узла будет своя ступень."
		print "Цифры curl/uTLS - отбор кандидатов; решают ПК и айфон."
	}' "$RUN/counts.tsv" > "$RUN/report.txt"
}

# ---------------------------------------------------------------- команды
do_status() {
	if [ ! -f "$STATUS" ]; then echo "ytbest ещё не запускался."; return; fi
	. "$STATUS" 2>/dev/null
	case "$state" in
		running)
			P=0; [ "${total:-0}" -gt 0 ] && P=$((cnt * 100 / total))
			EL=$(( ($(date +%s) - ${started:-0}) / 60 ))
			echo "Идёт: $P % ($cnt из $total проверок), сейчас $mode $node; прошло $EL мин из ~$est_min."
			alive || echo "ВНИМАНИЕ: процесс не найден - возможно, прерван. Проверьте Zapret2: /etc/init.d/zapret2 start" ;;
		analyzing) echo "Подсчёт результатов..." ;;
		done) echo "Готово. Отчёт: $0 report   Блок: $0 block" ;;
		stopped) echo "Остановлено. Zapret2 возвращён (если работал)." ;;
		starting) echo "Запускается..." ;;
		*) echo "Состояние: $state" ;;
	esac
	tail -3 "$RUN/run.log" 2>/dev/null
}

do_selftest() {
	echo "ytbest $VER"
	[ -f "$BC" ] && echo "blockcheck2: есть ($BC)" || echo "blockcheck2: НЕТ ($BC)"
	[ -s "$BASE/candidates.txt" ] && echo "кандидатов: $(grep -vcE '^[[:space:]]*(#|$)' "$BASE/candidates.txt")" || echo "кандидатов: файл не найден"
	[ -s "$BASE/nodes.txt" ] && echo "узлов в nodes.txt: $(grep -vcE '^[[:space:]]*(#|$)' "$BASE/nodes.txt")"
	if [ -x "$UTLS" ]; then
		# iana.org по фиксированному адресу: проверка, что utlscurl работает и шлёт браузерный hello
		T=$("$UTLS" -w "%{time_total}" --connect-to iana.org::192.0.43.8 -Ss --max-time 8 --tlsv1.3 https://iana.org -o /dev/null 2>"$RUN/selftest.err")
		R=$?
		if [ "$R" = 0 ]; then echo "utlscurl: работает (iana.org за ${T} с, отпечаток браузера Chrome)"
		else echo "utlscurl: ошибка $R: $(head -1 "$RUN/selftest.err")"; fi
	else
		echo "utlscurl: нет файла $UTLS — доступен только режим -m curl"
	fi
	if [ -x "$SNIFF" ]; then
		"$SNIFF" -i br-lan,tailscale0 -t 1 -f googlevideo.com >/dev/null 2>"$RUN/selftest.err" \
			&& echo "ytsniff: работает ($(head -1 "$RUN/selftest.err" | sed 's/ytsniff: //'))" \
			|| echo "ytsniff: ошибка: $(head -1 "$RUN/selftest.err")"
	else
		echo "ytsniff: нет файла $SNIFF — команды nodes/auto недоступны"
	fi
	echo "свободно во флеше: $(df -h /overlay 2>/dev/null | awk 'NR==2{print $4}')"
	if W=$(busy_other); then echo "сейчас занято: $W"; else echo "занятых тестов нет — можно запускать"; fi
}

do_stop() {
	if alive; then
		kill "$(cat "$PIDF")" 2>/dev/null
		for i in 1 2 3 4 5 6 7 8; do alive || break; sleep 1; done
		alive && kill -9 "$(cat "$PIDF")" 2>/dev/null
	fi
	pkill -f '[b]lockcheck2.sh' 2>/dev/null
	sleep 1
	nft list tables 2>/dev/null | grep -q 'inet zapret$' && nft delete table inet zapret 2>/dev/null
	restore_zapret
	rm -f "$PIDF"
	echo "state=stopped" > "$STATUS"
	echo "Остановлено. Zapret2: $(pgrep nfqws2 >/dev/null && echo работает || echo 'НЕ запущен (если должен - /etc/init.d/zapret2 start)')"
}

case "$1" in
	start) shift; do_start "$@" ;;
	_run) shift; do_run "$@" ;;
	_analyze) shift; analyze "$@"; cat "$RUN/report.txt" ;;
	status) do_status ;;
	stop) do_stop ;;
	selftest) do_selftest ;;
	nodes) shift; do_nodes "$@" ;;
	auto) shift
		SEC=180
		case "$1" in ''|-*) ;; *) SEC=$1; shift ;; esac
		do_nodes "$SEC" || exit 1
		echo
		do_start "$@" ;;
	report) cat "$BASE/last_report.txt" 2>/dev/null || echo "Отчёта ещё нет." ;;
	block) cat "$BASE/last_block.txt" 2>/dev/null || echo "Блока ещё нет." ;;
	*) usage ;;
esac
