module("L_VeraAlexa1", package.seeall)

local _PLUGIN_NAME = "VeraAlexa"
local _PLUGIN_VERSION = "0.1"

local debugMode = false
local openLuup = false

local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1
local masterID = -1

-- SIDS
local MYSID								= "urn:bochicchio-com:serviceId:VeraAlexa1"
local HASID								= "urn:micasaverde-com:serviceId:HaDevice1"

-- COMMANDS
local COMMANDS_SPEAK					= "-e speak:%s -d %q"
local COMMANDS_SETVOLUME				= "-e vol:%s -d %q"
local COMMANDS_GETVOLUME				= "-q -d %q | grep -E '\"volume\":([0-9])*' -o | grep -E -o '([0-9])*'"
local BIN_PATH = "/storage/alexa"

TASK_HANDLE = nil

-- libs
local lfs = require "lfs"
local json = require("dkjson")    

--- ***** GENERIC FUNCTIONS *****
local function dump(t, seen)
    if t == nil then return "nil" end
    if seen == nil then seen = {} end
    local sep = ""
    local str = "{ "
    for k, v in pairs(t) do
        local val
        if type(v) == "table" then
            if seen[v] then
                val = "(recursion)"
            else
                seen[v] = true
                val = dump(v, seen)
            end
        elseif type(v) == "string" then
            if #v > 255 then
                val = string.format("%q", v:sub(1, 252) .. "...")
            else
                val = string.format("%q", v)
            end
        elseif type(v) == "number" and (math.abs(v - os.time()) <= 86400) then
            val = tostring(v) .. "(" .. os.date("%x.%X", v) .. ")"
        else
            val = tostring(v)
        end
        str = str .. sep .. k .. "=" .. val
        sep = ", "
    end
    str = str .. " }"
    return str
end

local function L(msg, ...) -- luacheck: ignore 212
    local str
    local level = 50
    if type(msg) == "table" then
        str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg)
        level = msg.level or level
    else
        str = _PLUGIN_NAME .. ": " .. tostring(msg)
    end
    str = string.gsub(str, "%%(%d+)", function(n)
        n = tonumber(n, 10)
        if n < 1 or n > #arg then return "nil" end
        local val = arg[n]
        if type(val) == "table" then
            return dump(val)
        elseif type(val) == "string" then
            return string.format("%q", val)
        elseif type(val) == "number" and math.abs(val - os.time()) <= 86400 then
            return tostring(val) .. "(" .. os.date("%x.%X", val) .. ")"
        end
        return tostring(val)
    end)
    luup.log(str, level)
end

local function getVarNumeric(name, dflt, dev, sid)
    local s = luup.variable_get(sid, name, dev) or ""
    if s == "" then return dflt end
    s = tonumber(s)
    return (s == nil) and dflt or s
end

local function D(msg, ...)
    debugMode = getVarNumeric("DebugMode", 0, masterID, MYSID) == 1

    if debugMode then
        local t = debug.getinfo(2)
        local pfx = _PLUGIN_NAME .. "(" .. tostring(t.name) .. "@" ..
                        tostring(t.currentline) .. ")"
        L({msg = msg, prefix = pfx}, ...)
    end
end

local function setVar(sid, name, val, dev)
    val = (val == nil) and "" or tostring(val)
    local s = luup.variable_get(sid, name, dev) or ""
    D("setVar(%1,%2,%3,%4) old value %5", sid, name, val, dev, s)
    if s ~= val then
        luup.variable_set(sid, name, val, dev)
        return true, s
    end
    return false, s
end

local function getVar(name, dflt, dev, sid)
    local s = luup.variable_get(sid, name, dev) or ""
    if s == "" then return dflt end
    return (s == nil) and dflt or s
end

local function split(str, sep)
    if sep == nil then sep = "," end
    local arr = {}
    if #(str or "") == 0 then return arr, 0 end
    local rest = string.gsub(str or "", "([^" .. sep .. "]*)" .. sep,
        function(m)
            table.insert(arr, m)
            return ""
        end)
    table.insert(arr, rest)
    return arr, #arr
end

local function map(arr, f, res)
    res = res or {}
    for ix, x in ipairs(arr) do
        if f then
            local k, v = f(x, ix)
            res[k] = (v == nil) and x or v
        else
            res[x] = x
        end
    end
    return res
end

local function initVar(name, dflt, dev, sid)
    local currVal = luup.variable_get(sid, name, dev)
    if currVal == nil then
        luup.variable_set(sid, name, tostring(dflt), dev)
        return tostring(dflt)
    end
    return currVal
end
3
function os.capture(cmd, raw)
    local handle = assert(io.popen(cmd, 'r'))
    local output = assert(handle:read('*a'))
    
    handle:close()
    
    if raw then 
        return output 
    end
   
    output = string.gsub(
        string.gsub(
            string.gsub(output, '^%s+', ''), 
            '%s+$', 
            ''
        ), 
        '[\n\r]+',
        ' '
    )
   
   return output
end

-- ** PLUGIN CODE **
local ttsQueue = {}

function addToQueue(device, settings)
	L("TTS added to queue for %1", device)
	if not ttsQueue[device] then ttsQueue[device] = {} end

	-- TODO: handle repeat param
	table.insert(ttsQueue[device], settings)

	-- last one in queue, let's process directly
	if #ttsQueue[device] == 1 then
		D("Only one in queue, let's play %1", device)
		sayTTS(device, settings)
	else
		luup.call_delay("checkQueue", 50, device)
	end
end

local function executeCommand(command, capture)
	D("Executing command: %1", command)

	-- TODO: try/catch	
	local r = os.capture(command)
	D("Response from Alexa.sh: %1", r)
	
	return r
end

local function buildCommand(settings)
	local args = "export EMAIL=%q && export PASSWORD=%q && export SPEAKVOL=%s && export TTS_LOCALE=%s && export LANGUAGE=%s && export AMAZON=%s && export ALEXA=%s && export TMP=%q && %s/alexa_remote_control_plain.sh "
	local username = getVar("Username", "", masterID, MYSID)
	local password = getVar("Password", "", masterID, MYSID)
	local volume = getVarNumeric("DefaultVolume", "", masterID, MYSID)
	local defaultDevice = getVar("DefaultEcho", "", masterID, MYSID)
	local alexaHost = getVar("AlexaHost", "", masterID, MYSID)
	local amazonHost = getVar("AmazonHost", "", masterID, MYSID)
	local language = getVar("Language", "", masterID, MYSID)

	local command = string.format(args, username, password,
										(settings.Volume or volume),
										(settings.Language or language), (settings.Language or language),
										amazonHost, alexaHost,
										BIN_PATH, BIN_PATH,
										(settings.Text or "Test"),
										(settings.GroupZones or defaultDevice))
	return command
end

function sayTTS(device, settings)
	local volume = getVarNumeric("DefaultVolume", "", masterID, MYSID)
	local defaultDevice = getVar("DefaultEcho", "", masterID, MYSID)

	local command = buildCommand(settings) ..
					string.format(COMMANDS_SPEAK,
                                    string.gsub((settings.Text or "Test"), "%s+", "_"),
									(settings.GroupZones or defaultDevice))


	executeCommand(command)
	L("Executing command: %1", command)

	-- wait for x seconds based on string length
	local timeout =  0.062 * string.len(settings.Text) + 1
	luup.call_delay("checkQueue", timeout, device)
end

function setVolume(volume, device, settings)
	local defaultDevice = getVar("DefaultEcho", "", masterID, MYSID)
	local echoDevice = (settings.GroupZones or defaultDevice)

	local finalVolume = settings.DesiredVolume or 0
	D("Volume requested for %2: %1", finalVolume, echoDevice)

	if settings.DesiredVolume == nil and volume ~= 0 then
		-- alexa doesn't support +1/-1, so we must first get current volume
		local command = buildCommand(settings) ..
								string.format(COMMANDS_GETVOLUME, echoDevice)
		local r = executeCommand(command)
		local currentVolume = tonumber(r)
		D("Volume for %2: %1", currentVolume, echoDevice)
		finalVolume = currentVolume + (volume * 10)
	end

	D("Volume for %2 set to: %1", finalVolume, echoDevice)
	local command = buildCommand(settings) ..
						string.format(COMMANDS_SETVOLUME, finalVolume, echoDevice)

	executeCommand(command)
end

function checkQueue(device)
	D("checkQueue: %1", device)

	-- is queue now empty?
	table.remove(ttsQueue[device], 1)
	if #ttsQueue[device] == 0 then
		D("checkQueue: %1 no more items in queue", device)
		return true
	end

	D("checkQueue: %1 play next", device)
	-- get the next one
	sayTTS(device, ttsQueue[device][1])
end

function isFile(name)
    if type(name)~="string" then return false end
    return os.rename(name,name) and true or false
end

function setupScripts()
	D("Setup in progress")
	-- mkdir
	lfs.mkdir(BIN_PATH)

	-- download script from github
	os.execute("curl https://raw.githubusercontent.com/thorsten-gehrig/alexa-remote-control/master/alexa_remote_control_plain.sh > " .. BIN_PATH .. "/alexa_remote_control_plain.sh")

	-- add permission using lfs
	os.execute("chmod 777 " .. BIN_PATH .. "/alexa_remote_control_plain.sh")
	-- TODO: fix it and use lfs
	-- lfs.attributes(BIN_PATH .. "/alexa_remote_control_plain.sh", {permissions = "777"})

	-- first command must be executed to create cookie and such
	executeCommand(buildCommand({}))

	D("Setup completed")
end

function startPlugin(devNum)
    masterID = devNum

    L("Plugin starting: %1 - v%2", _PLUGIN_NAME, _PLUGIN_VERSION)

	-- decect OpenLuup
	for k,v in pairs(luup.devices) do
		if v.device_type == "openLuup" then
			openLuup = true
			D("Running on OpenLuup: %1", openLuup)

			BIN_PATH = "/etc/cmh-ludl/VeraAlexa"
		end
	end

	-- init default vars
    initVar("DebugMode", 0, devNum, MYSID)
	initVar("Username", "youraccount@amazon.com", devNum, MYSID)
    initVar("Password", "password", devNum, MYSID)
	initVar("DefaultEcho", "Bedroom", devNum, MYSID)
	initVar("DefaultVolume", 50, devNum, MYSID)
	-- default for US
	initVar("Language", "en-us", devNum, MYSID)
	initVar("AlexaHost", "pitangui.amazon.com", devNum, MYSID)
	initVar("AmazonHost", "amazon.com", devNum, MYSID)

	-- categories
	if luup.attr_get("category_num", devNum) == nil then
	    luup.attr_set("category_num", "15", devNum)			-- A/V
	end

	-- check for configured flag and for the script
	local configured = getVarNumeric("Configured", 0, masterID, HASID)
	if configured == 0 or not isFile(BIN_PATH .. "/alexa_remote_control_plain.sh") then
		setupScripts()
		setVar(HASID, "Configured", 1, devNum)
	else
		D("Engine already correctly configured: skipping config")
	end

	-- randomizer
	math.randomseed(tonumber(tostring(os.time()):reverse():sub(1,6)))

    -- status
    luup.set_failure(0, devNum)
    return true, "Ready", _PLUGIN_NAME
end