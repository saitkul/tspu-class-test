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
	entry({"admin", "services", "tspu-test", "applyzapret"},
		call("action_applyzapret")).leaf = true
	entry({"admin", "services", "tspu-test", "rollbackzapret"},
		call("action_rollbackzapret")).leaf = true
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

-- Применение готовой стратегии в /etc/config/zapret2 (запрос владельца проекта).
-- Сценарий передаётся в /tmp/tspu_apply.script, вся логика - в CLI (applyzapret):
-- валидация, резервная копия, вставка секции перед first-match-wins, uci-валидация.
function action_applyzapret()
	local http = luci.http
	local lbl = tostring(http.formvalue("label") or "tspu-test"):gsub("'", "")
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
	if hl ~= "" and not hl:match("^zapret_hosts_[A-Za-z0-9_.%-]+%.txt$") then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid hostlist name")
		return
	end
	local hf = io.open("/tmp/tspu_apply.hostlist", "w")
	if hf then hf:write(hl) hf:close() end
	local f = io.open("/tmp/tspu_apply.script", "w")
	if not f then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=cannot write temp file")
		return
	end
	-- Выбор списка хостов из UI (имя zapret_hosts_*.txt, без путей)
	local hl = tostring(http.formvalue("hostlist") or "")
	if hl ~= "" and not hl:match("^zapret_hosts_[A-Za-z0-9_.%-]+%.txt$") then
		http.prepare_content("text/plain; charset=utf-8")
		http.write("state=error msg=invalid hostlist name")
		return
	end
	local hf = io.open("/tmp/tspu_apply.hostlist", "w")
	if hf then hf:write(hl) hf:close() end
	f:write(script)
	f:close()
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec(string.format("/usr/bin/tspu-test applyzapret '%s' 2>&1", lbl)))
end

function action_rollbackzapret()
	http.prepare_content("text/plain; charset=utf-8")
	http.write(luci.sys.exec("/usr/bin/tspu-test rollbackzapret 2>&1"))
end
