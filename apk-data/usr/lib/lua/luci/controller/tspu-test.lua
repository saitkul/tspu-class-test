-- ============================================================
--  luci-app-tspu-test: контроллер страницы и RPC-эндпоинтов.
--  Страница - серверный шаблон (test.htm), эндпоинты - текстовые.
--  Ядро: /usr/bin/tspu-test (tspu-class-test v2.2).
-- ============================================================

module("luci.controller.tspu-test", package.seeall)

function index()
	if not nixio.fs.access("/usr/bin/tspu-test") then
		return
	end

	local page = entry({"admin", "services", "tspu-test"},
		template("tspu-test/test"), _("TSPU test"), 65)
	page.dependent = false

	entry({"admin", "services", "tspu-test", "status"},
		call("action_status")).leaf = true
	entry({"admin", "services", "tspu-test", "start"},
		call("action_start")).leaf = true
	entry({"admin", "services", "tspu-test", "stop"},
		call("action_stop")).leaf = true
	entry({"admin", "services", "tspu-test", "clearlog"},
		call("action_clear")).leaf = true
	entry({"admin", "services", "tspu-test", "log"},
		call("action_log")).leaf = true
	entry({"admin", "services", "tspu-test", "download"},
		call("action_download")).leaf = true
	entry({"admin", "services", "tspu-test", "quicstart"},
		call("action_quic_start")).leaf = true
	entry({"admin", "services", "tspu-test", "quicstop"},
		call("action_quic_stop")).leaf = true
	entry({"admin", "services", "tspu-test", "quicstatus"},
		call("action_quic_status")).leaf = true
	entry({"admin", "services", "tspu-test", "quicpage"},
		call("action_quic_page")).leaf = true
end

-- Белый список скачиваемых логов: никаких подстановок путей из запроса
local LOG_FILES = {
	short  = { path = "/tmp/class_test.log.short", name = "class_test.log.short" },
	full   = { path = "/tmp/class_test.log",       name = "class_test.log" },
	runlog = { path = "/tmp/tspu_test_run.log",    name = "tspu_test_run.log" },
	quicshort = { path = "/opt/curl/quic_test.log.short", name = "quic_test.log.short" },
	quicfull  = { path = "/opt/curl/quic_test.log",       name = "quic_test.log" },
}

function action_download()
	local http = luci.http
	local which = tostring(http.formvalue("which") or "")
	local spec = LOG_FILES[which]
	if not spec or not io.open(spec.path, "r") then
		http.status(404, "Not Found")
		http.prepare_content("text/plain; charset=utf-8")
		http.write("Файл лога не найден. Он создаётся после первого запуска теста.")
		return
	end
	local f = io.open(spec.path, "r")
	local data = f:read("*a")
	f:close()
	http.header("Content-Disposition",
		'attachment; filename="' .. spec.name .. '"')
	http.prepare_content("text/plain; charset=utf-8")
	http.write(data)
end

local function arg_clean(value, pattern, default)
	value = tostring(value or "")
	if not value:match(pattern) then
		return default
	end
	return value
end

-- Версия пакета: файл кладёт сборщик (build.py / apk mkpkg), содержит, например, 1.1.4
local function pkg_version()
	local f = io.open("/usr/share/tspu-test/version", "r")
	if not f then
		return nil
	end
	local v = f:read("*l") or ""
	f:close()
	if v:match("^%d+[%.%d%-r]*$") then
		return v
	end
	return nil
end

function action_status()
	luci.http.prepare_content("text/plain; charset=utf-8")
	local out = luci.sys.exec("/usr/bin/tspu-test status 2>&1")
	local ver = pkg_version()
	if ver then
		out = out .. "version=" .. ver .. "\n"
	end
	luci.http.write(out)
end

function action_start()
	local http = luci.http
	local dom = tostring(http.formvalue("domain") or "")
	-- Невалидный домен — ошибка пользователю, а не молчаливая подмена
	if not dom:match("^[%w%.%-]+$") or dom:match("^%-") then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid domain (use letters, digits, dots, dashes)")
		return
	end
	local rep = arg_clean(http.formvalue("repeats"), "^%d+$", "3")
	local tmo = arg_clean(http.formvalue("wait"), "^%d+%.?%d*$", "2.5")
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format(
		"/usr/bin/tspu-test start '%s' '%s' '%s' 2>&1", dom, rep, tmo)))
end

function action_stop()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test stop 2>&1"))
end

function action_clear()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test clearlog 2>&1"))
end

function action_log()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test log 2>&1"))
end

-- ============================================================
--  QUIC-тест: подготовка (curl13 + скрипт ставятся автоматически)
--  и фоновый запуск quic_class_test.sh. Статус — /tmp/tspu_quic.status,
--  вывод — /opt/curl/quic_test.log. Всё делает quic-prepare.sh из пакета.
-- ============================================================
local QUIC_STATUS = "/tmp/tspu_quic.status"

function action_quic_status()
	luci.http.prepare_content("text/plain; charset=utf-8")
	local st = ""
	local f = io.open(QUIC_STATUS, "r")
	if f then st = f:read("*a") or ""; f:close() end
	if st == "" then
		-- статус не появился: показать ошибку запуска подготовителя, если была
		local g = io.open("/tmp/tspu_quic_launcher.log", "r")
		if g then
			local l = g:read("*l") or ""
			g:close()
			if l ~= "" then st = "state=error msg=" .. l end
		end
	end
	if st == "" then st = "state=none" end
	local alive = "0"
	if os.execute("pgrep -f 'quic_class_test.sh|quic-prepare.sh' >/dev/null 2>&1") == 0 then
		alive = "1"
	end
	-- Хвост вывода теста: \r-ленту прогресса разворачиваем в строки
	local tail = luci.sys.exec(
		"tail -n 200 /opt/curl/quic_test.log 2>/dev/null | tr '\\r' '\\n' | tail -n 60")
	luci.http.write(st .. "alive=" .. alive .. "\n--QUICLOG--\n" .. tail)
end

function action_quic_start()
	local http = luci.http
	local dom = tostring(http.formvalue("domain") or "www.youtube.com")
	if not dom:match("^[%w%.%- ]+$") or dom:match("^%-") then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid domain (use letters, digits, dots, dashes, spaces)")
		return
	end
	http.prepare_content("text/plain; charset=utf-8")
	-- Фоновый запуск. sleep 1 в родителе — как в CLI do_start: канал rpcd
	-- не закрывается мгновенно, ребёнок успевает стартовать (иначе умер
	-- сразу, без единой записи статуса).
	http.write(luci.sys.exec(string.format(
		"/bin/sh -c 'sh /usr/share/tspu-test/quic-prepare.sh \"%s\" >/tmp/tspu_quic_launcher.log 2>&1 &' ; sleep 1; echo state=submitted",
		dom)))
end

function action_quic_page()
	local http = luci.http
	local stop = http.formvalue("stop")
	local run = http.formvalue("run")
	local dom = tostring(http.formvalue("domain") or "www.youtube.com")

	if stop then
		luci.sys.exec("pkill -f 'quic-prepare.sh' 2>/dev/null; pkill -f 'quic_class_test.sh' 2>/dev/null")
		os.execute("sleep 1")
	end
	if run and dom:match("^[%w%.%- ]+$") and not dom:match("^%-") then
		luci.sys.exec(string.format(
			"/bin/sh -c 'sh /usr/share/tspu-test/quic-prepare.sh \"%s\" >/tmp/tspu_quic_launcher.log 2>&1 &' ; sleep 1", dom))
	end

	local st = luci.sys.exec(
		"cat /tmp/tspu_quic.status 2>/dev/null; "
		.. "pgrep -f 'quic_class_test.sh|quic-prepare.sh' >/dev/null 2>&1 && echo alive=1 || echo alive=0")
	local st_state = st:match("state=([a-z]+)") or "none"
	local st_msg = st:match("msg=([^%c]*)") or ""
	local alive = st:match("alive=(%d)") or "0"
	local running = (st_state == "installing" or st_state == "downloading" or st_state == "running") and alive == "1"

	local tail = luci.sys.exec(
		"tail -n 200 /opt/curl/quic_test.log 2>/dev/null | tail -n 160")

	local txt = "не запускался"
	if stop then txt = "остановлено"
	elseif st_state == "installing" then txt = "подготовка: копирую скрипт в /opt/curl"
	elseif st_state == "downloading" then txt = "скачиваю h3-curl (" .. st_msg .. ")"
	elseif st_state == "running" then txt = "идёт QUIC-тест (10–20 минут)"
	elseif st_state == "done" then txt = "завершён"
	elseif st_state == "error" then txt = "ошибка подготовки: " .. st_msg
	end

	local head_refresh = ""
	if running then
		head_refresh = "<meta http-equiv='refresh' content='5'>"
	end

	local form = ""
	if not running and not stop then
		form = "<form method='get'>"
			.. "<input type='hidden' name='run' value='1'>"
			.. "<input name='domain' value='" .. dom .. "' style='width:100%;max-width:420px'>"
			.. "<button type='submit'>Установить и запустить</button>"
			.. "</form>"
	end

	local body = "<!DOCTYPE html><html><head><meta charset='utf-8'>" .. head_refresh
		.. "<title>TSPU test — QUIC</title></head>"
		.. "<body style='font-family:sans-serif; max-width:900px; margin:24px auto'>"
		.. "<h2>TSPU test — QUIC-тест (UDP 443)</h2>"
		.. "<p>Ядро теста и h3-curl ставятся автоматически в /opt/curl. "
		.. "На время теста Zapret2 останавливается и возвращается по завершении. "
		.. "Видео тестируйте по узлу rr1---sn-….googlevideo.com (F12 → Network → videoplayback); "
		.. "корневой googlevideo.com закрывают наглухо.</p>"
		.. "<p><b>Статус:</b> " .. txt .. "</p>"
		.. form
		.. "<p><a href='" .. luci.dispatcher.build_url("admin/services/tspu-test/quicpage") .. "'>Обновить страницу</a> · "
		.. "<a href='" .. luci.dispatcher.build_url("admin/services/tspu-test/quicpage") .. "?stop=1'>Остановить тест</a> · "
		.. "<a href='" .. luci.dispatcher.build_url("admin/services/tspu-test/download") .. "?which=quicshort'>Краткий лог</a> · "
		.. "<a href='" .. luci.dispatcher.build_url("admin/services/tspu-test/download") .. "?which=quicfull'>Полный лог</a> · "
		.. "<a href='" .. luci.dispatcher.build_url("admin/services/tspu-test") .. "'>← Вернуться в TSPU test</a></p>"
		.. "<pre style='background:#111;color:#ccc;padding:12px;overflow:auto;font-size:12px'>"
		.. tail:gsub("<", "&lt;") .. "</pre>"
		.. "</body></html>"
	luci.http.prepare_content("text/html; charset=utf-8")
	luci.http.write(body)
end

function action_quic_stop()
	luci.http.prepare_content("text/plain; charset=utf-8")
	-- TERM скрипту: его trap убивает blockcheck2 и возвращает Zapret2
	luci.http.write(luci.sys.exec(
		"pkill -f 'quic-prepare.sh' 2>/dev/null; pkill -f 'quic_class_test.sh' 2>/dev/null; "
		.. "echo state=stopped; echo"))
end
