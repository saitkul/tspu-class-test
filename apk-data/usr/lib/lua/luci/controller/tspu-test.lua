-- ============================================================
--  luci-app-tspu-test: контроллер страницы и RPC-эндпоинтов.
--  Страница - серверный шаблон (test.htm), эндпоинты - текстовые.
--  Ядро: /usr/bin/tspu-test (tspu-class-test v3.0).
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
	entry({"admin", "services", "tspu-test", "applyzapret"},
		call("action_applyzapret")).leaf = true

	-- Прод-проба
	entry({"admin", "services", "tspu-test", "prodstart"},
		call("action_prodstart")).leaf = true
	entry({"admin", "services", "tspu-test", "prodstop"},
		call("action_prodstop")).leaf = true
	entry({"admin", "services", "tspu-test", "prodstatus"},
		call("action_prodstatus")).leaf = true
	entry({"admin", "services", "tspu-test", "prodlog"},
		call("action_prodlog")).leaf = true
	entry({"admin", "services", "tspu-test", "prodclear"},
		call("action_prodclear")).leaf = true
	-- Валидатор
	entry({"admin", "services", "tspu-test", "valstart"},
		call("action_valstart")).leaf = true
	entry({"admin", "services", "tspu-test", "valstop"},
		call("action_valstop")).leaf = true
	entry({"admin", "services", "tspu-test", "valstatus"},
		call("action_valstatus")).leaf = true
	entry({"admin", "services", "tspu-test", "vallog"},
		call("action_vallog")).leaf = true
	entry({"admin", "services", "tspu-test", "valclear"},
		call("action_valclear")).leaf = true
	entry({"admin", "services", "tspu-test", "valreport"},
		call("action_valreport")).leaf = true
	-- Канарейка
	entry({"admin", "services", "tspu-test", "canarystart"},
		call("action_canarystart")).leaf = true
	entry({"admin", "services", "tspu-test", "canarystop"},
		call("action_canarystop")).leaf = true
	entry({"admin", "services", "tspu-test", "canarystatus"},
		call("action_canarystatus")).leaf = true
	entry({"admin", "services", "tspu-test", "canarylog"},
		call("action_canarylog")).leaf = true
	entry({"admin", "services", "tspu-test", "profiles"},
		call("action_profiles")).leaf = true
	-- ECH-проба
	entry({"admin", "services", "tspu-test", "ech"},
		call("action_ech")).leaf = true

	-- Канарейка: очистка лога
	entry({"admin", "services", "tspu-test", "canaryclear"},
		call("action_canaryclear")).leaf = true

	-- Подбор (ytbest): узлы, запуск, стоп, статус, отчёт, блок, selftest, кандидаты
	entry({"admin", "services", "tspu-test", "ytnodes"},
		call("action_ytnodes")).leaf = true
	entry({"admin", "services", "tspu-test", "ytstart"},
		call("action_ytstart")).leaf = true
	entry({"admin", "services", "tspu-test", "ytstop"},
		call("action_ytstop")).leaf = true
	entry({"admin", "services", "tspu-test", "ytstatus"},
		call("action_ytstatus")).leaf = true
	entry({"admin", "services", "tspu-test", "ytreport"},
		call("action_ytreport")).leaf = true
	entry({"admin", "services", "tspu-test", "ytblock"},
		call("action_ytblock")).leaf = true
	entry({"admin", "services", "tspu-test", "ytselftest"},
		call("action_ytselftest")).leaf = true
	entry({"admin", "services", "tspu-test", "ytcand"},
		call("action_ytcand")).leaf = true
	entry({"admin", "services", "tspu-test", "ytclear"},
		call("action_ytclear")).leaf = true
	entry({"admin", "services", "tspu-test", "ytapply"},
		call("action_ytapply")).leaf = true
	entry({"admin", "services", "tspu-test", "transport"},
		call("action_transport")).leaf = true
	entry({"admin", "services", "tspu-test", "ytremap"},
		call("action_ytremap")).leaf = true
	entry({"admin", "services", "tspu-test", "ytremapapply"},
		call("action_ytremapapply")).leaf = true
	entry({"admin", "services", "tspu-test", "ytremapoff"},
		call("action_ytremapoff")).leaf = true
end

-- ===== Подбор (ytbest) =====
function action_ytnodes()
	local http = luci.http
	local sec = tostring(http.formvalue("sec") or "180")
	sec = sec:gsub("[^%d]", "")
	if sec == "" then sec = "180" end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test yt nodesbg '%s' 2>&1", sec)))
end

function action_ytstart()
	local http = luci.http
	local sec = tostring(http.formvalue("sec") or "180")
	sec = sec:gsub("[^%d]", "")
	if sec == "" then sec = "180" end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test yt auto '%s' 2>&1", sec)))
end

function action_ytstop()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt stop 2>&1"))
end

function action_ytstatus()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt status 2>&1"))
end

function action_ytreport()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt report 2>&1"))
end

function action_ytblock()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt block 2>&1"))
end

function action_ytselftest()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt selftest 2>&1"))
end

function action_ytcand()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt cand 2>&1"))
end

function action_ytclear()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt clear 2>&1"))
end

function action_ytapply()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt apply 2>&1"))
end

-- ===== Транспорт (лайт-матрица, только измерения; фоновый запуск) =====
function action_transport()
	local http = luci.http
	local act = tostring(http.formvalue("act") or "")
	if act ~= "start" then act = "" end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test transport '%s' 2>&1", act)))
end

-- ===== GGC-ремап (dnsmasq; apply перезапускает dnsmasq — краткий DNS-перерыв) =====
function action_ytremap()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt remap gen 2>&1"))
end

function action_ytremapapply()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt remap apply 2>&1"))
end

function action_ytremapoff()
	local http = luci.http
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test yt remap off 2>&1"))
end

local function _dom_ok(dom)
	return dom and dom:match("^[%w%.%-]+$") and not dom:match("^%-")
end

-- ===== Прод-проба =====
function action_prodstart()
	local http = luci.http
	local dom = tostring(http.formvalue("domain") or "")
	if not _dom_ok(dom) then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid domain")
		return
	end
	local dur = tostring(http.formvalue("dur") or "30")
	dur = dur:gsub("[^%d]", "")
	if dur == "" then dur = "30" end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test prod start '%s' '%s' 2>&1", dom, dur)))
end

function action_prodstop()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test prod stop 2>&1"))
end

function action_prodstatus()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test prod status 2>&1"))
end

function action_prodlog()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test prod log 2>&1"))
end

function action_prodclear()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test prod clear 2>&1"))
end

-- ===== Валидатор =====
function action_valstart()
	local http = luci.http
	local txt = tostring(http.formvalue("text") or "")
	-- Проверка домена ДО записи файла (ревью 2.5: файл оставался от прошлого ввода)
	local dom = tostring(http.formvalue("domain") or "")
	if not _dom_ok(dom) then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid domain")
		return
	end
	local f = io.open("/tmp/tspu_validate.txt", "w")
	if not f then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=cannot write temp file")
		return
	end
	f:write(txt)
	f:close()
	local rep = tostring(http.formvalue("rep") or "2")
	rep = rep:gsub("[^%d]", "")
	if rep == "" then rep = "2" end
	local utls = tostring(http.formvalue("utls") or "0")
	if utls ~= "1" then utls = "0" end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test validate start '%s' '%s' '%s' 2>&1", dom, rep, utls)))
end

function action_valstop()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test validate stop 2>&1"))
end

function action_valstatus()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test validate status 2>&1"))
end

function action_vallog()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test validate log 2>&1"))
end

function action_valclear()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test validate clear 2>&1"))
end

function action_valreport()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test validate report 2>&1"))
end

-- ===== Канарейка =====
function action_canarystart()
	local http = luci.http
	local dom = tostring(http.formvalue("domain") or "")
	if not _dom_ok(dom) then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid domain")
		return
	end
	local iv = tostring(http.formvalue("iv") or "300")
	iv = iv:gsub("[^%d]", "")
	if iv == "" then iv = "300" end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test canary start '%s' '%s' 2>&1", dom, iv)))
end

function action_canarystop()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test canary stop 2>&1"))
end

function action_canarystatus()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test canary status 2>&1"))
end

function action_canarylog()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test canary log 2>&1"))
end

function action_profiles()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test profiles 2>&1"))
end

function action_canaryclear()
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(luci.sys.exec("/usr/bin/tspu-test canary clear 2>&1"))
end

-- ===== ECH-проба =====
function action_ech()
	local http = luci.http
	local dom = tostring(http.formvalue("domain") or "")
	if not _dom_ok(dom) then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid domain")
		return
	end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test ech '%s' 2>&1", dom)))
end

-- Белый список скачиваемых логов: никаких подстановок путей из запроса
local LOG_FILES = {
	short  = { path = "/tmp/class_test.log.short", name = "class_test.log.short" },
	full   = { path = "/tmp/class_test.log",       name = "class_test.log" },
	runlog = { path = "/tmp/tspu_test_run.log",    name = "tspu_test_run.log" },
}

function action_download()
	local http = luci.http
	local which = tostring(http.formvalue("which") or "")
	local spec = LOG_FILES[which]
	local h = spec and io.open(spec.path, "r")
	if not h then
		http.status(404, "Not Found")
		http.prepare_content("text/plain; charset=utf-8")
		http.write("Файл лога не найден. Он создаётся после первого запуска теста.")
		return
	end
	local data = h:read("*a")
	h:close()
	if data == "" then
		-- Пустой лог = blockcheck2 ещё пишет (краткий лог появляется в конце прогона).
		-- 200 вместо 404: браузер показывает текст, а не «ошибка»
		http.header("Content-Disposition", 'attachment; filename="' .. spec.name .. '"')
		http.prepare_content("text/plain; charset=utf-8")
		http.write("Лог ещё пишется (идёт проверка адаптивности или завершение прогона) — подождите несколько секунд и скачайте снова.")
		return
	end
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
	-- Несколько доменов через пробел: проверяем каждый по отдельности
	-- (невалидный домен — ошибка пользователю, а не молчаливая подмена)
	local parts, ok = {}, true
	for w in dom:gmatch("%S+") do
		if not w:match("^[%w%.%-]+$") or w:match("^%-") then ok = false; break end
		parts[#parts + 1] = w
	end
	if not ok or #parts == 0 then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid domain (use letters, digits, dots, dashes)")
		return
	end
	dom = table.concat(parts, " ")
	local rep = arg_clean(http.formvalue("repeats"), "^%d+$", "3")
	local tmo = arg_clean(http.formvalue("wait"), "^%d+%.?%d*$", "2.5")
	-- IPv6-проба: 4-й аргумент CLI "ipv6" - прогон дополнительно по IPv6
	local ip6 = tostring(http.formvalue("ipv6") or "")
	local cmd = string.format("/usr/bin/tspu-test start '%s' '%s' '%s'", dom, rep, tmo)
	if ip6 == "1" then cmd = cmd .. " 'ipv6'" end
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(cmd .. " 2>&1"))
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

-- Применение готовой стратегии в /etc/config/zapret2 (запрос владельца проекта).
-- Сценарий передаётся в /tmp/tspu_apply.script, вся логика - в CLI (applyzapret):
-- валидация, резервная копия, вставка секции перед first-match-wins, uci-валидация.
function action_applyzapret()
	local http = luci.http
	local lf = io.open("/tmp/tspu_apply.log", "a")
	if lf then lf:write(os.date("%Y-%m-%d %H:%M:%S") .. " apply label=" .. tostring(http.formvalue("label") or "?") .. "\n") lf:close() end
	local lbl = tostring(http.formvalue("label") or "tspu-test"):gsub("'", "")
	local dom = tostring(http.formvalue("domain") or "")
	if dom:match("[^%w%.%-]") then dom = "" end
	local script = tostring(http.formvalue("script") or "")
	if script ~= "@REMOVE@" and (#script < 8 or not script:match("^%-%-")) then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=script empty or does not start with --")
		return
	end
	-- Запрещены метасимволы shell: кавычки, $, ;, &, |, <, >, скобки, обратная кавычка
	if script:match("[`$;&|<>%(%)'\"]") then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=script contains forbidden characters")
		return
	end
	local hl = tostring(http.formvalue("hostlist") or "")
	if hl ~= "" and not hl:match("^[A-Za-z0-9_.%-]+$") then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid hostlist name")
		return
	end
	local hf = io.open("/tmp/tspu_apply.hostlist", "w")
	if hf then hf:write(hl) hf:close() end
	-- Фильтр L3 секции: ipv4 | ipv6 | both (по умолчанию ipv4)
	local l3 = tostring(http.formvalue("l3") or "ipv4")
	if l3 ~= "ipv4" and l3 ~= "ipv6" and l3 ~= "both" then l3 = "ipv4" end
	local lf = io.open("/tmp/tspu_apply.l3", "w")
	if lf then lf:write(l3) lf:close() end
	local f = io.open("/tmp/tspu_apply.script", "w")
	if not f then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=cannot write temp file")
		return
	end
	f:write(script)
	f:close()
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test applyzapret '%s' '%s' 2>&1", lbl, dom)))
end

