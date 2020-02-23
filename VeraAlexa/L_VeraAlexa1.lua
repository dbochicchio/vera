module("L_VeraAlexa1", package.seeall)

local _PLUGIN_NAME = "VeraAlexa"
local _PLUGIN_VERSION = "0.2.5"

local debugMode = false
local openLuup = false

local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1
local masterID = -1

-- SIDs
local MYSID                                 = "urn:bochicchio-com:serviceId:VeraAlexa1"
local HASID                                 = "urn:micasaverde-com:serviceId:HaDevice1"

-- COMMANDS
local COMMANDS_SPEAK					    = "-e speak:'%s' -d %q"
local COMMANDS_ROUTINE					    = "-e automation:\"%s\" -d %q"
local COMMANDS_SETVOLUME			        = "-e vol:%s -d %q"
local COMMANDS_GETVOLUME			        = "-q -d %q | grep -E '\"volume\":([0-9])*' -o | grep -E -o '([0-9])*'"
local BIN_PATH                              = "/storage/alexa"
local SCRIPT_NAME							= "alexa_remote_control_plain.sh"

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

local function getVarNumeric(sid, name, dflt, dev)
    local s = luup.variable_get(sid, name, dev) or ""
    if s == "" then return dflt end
    s = tonumber(s)
    return (s == nil) and dflt or s
end

local function D(msg, ...)
    debugMode = getVarNumeric(MYSID, "DebugMode", 0, masterID) == 1

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

local function getVar(sid, name, dflt, dev)
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

local function initVar(sid, name, dflt, dev)
    local currVal = luup.variable_get(sid, name, dev)
    if currVal == nil then
        luup.variable_set(sid, name, tostring(dflt), dev)
        return tostring(dflt)
    end
    return currVal
end

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

function checkQueue(device)
	local device = tonumber(device)

	if ttsQueue[device] == nil then ttsQueue[device] = {} end
	D("checkQueue: %1 - %2 in queue", device, #ttsQueue[device])
    
	-- is queue now empty?
	if #ttsQueue[device] == 0 then
		D("checkQueue: %1 - queue is empty", device)
		return true
	end

	D("checkQueue: %1 - play next", device)

	-- get the next one
	sayTTS(device, ttsQueue[device][1])
    
    -- remove from queue
    table.remove(ttsQueue[device], 1)
end

function addToQueue(device, settings)
	L("addToQueue: added to queue for %1", device)
	if ttsQueue[device] == nil then ttsQueue[device] = {} end

	local defaultBreak = getVar(MYSID, "DefaultBreak", 3, masterID)

	local startPlaying = #ttsQueue[device] == 0

    local howMany = tonumber(settings.Repeat or 1)
    D('addToQueue: before: %1', #ttsQueue[device])

	local useAnnoucements = getVarNumeric(MYSID, "UseAnnoucements", 0, masterID)
	if useAnnoucements == 1 then
		-- no need to repeat, just concatenate
		local text = ""
		for f = 1, howMany do
			text = text .. "<s>" .. settings.Text .. '</s><break time="' .. (f == howMany and 0 or defaultBreak) .. 's" />'
		end
		settings.Text = text

		table.insert(ttsQueue[device], settings)
	else
		-- format text and concatenate
		settings.Text = string.gsub(settings.Text, "%s+", "_")

	    for f = 1, howMany do
			table.insert(ttsQueue[device], settings)
		end
	end
    D('addToQueue: after: %1', #ttsQueue[device])

	if (startPlaying) then
		checkQueue(device)
	end
end

local function executeCommand(command, capture)
	D("Executing command: %1", command)

	-- TODO: try/catch	
	local response = os.capture(command)

	setVar(MYSID, "LatestResponse", r, devNum)
	D("Response from Alexa.sh: %1", response)

	return r
end

local function buildCommand(settings)
	local args = "export EMAIL=%q && export PASSWORD=%q && export SPEAKVOL=%s && export TTS_LOCALE=%s && export LANGUAGE=%s && export AMAZON=%s && export ALEXA=%s && export USE_ANNOUNCEMENT_FOR_SPEAK=%s && export TMP=%q && %s/" .. SCRIPT_NAME .. " "
	local username = getVar(MYSID, "Username", "", masterID)
	local password = getVar(MYSID, "Password", "", masterID) .. getVar(MYSID, "OneTimePassCode", "", masterID)
	local volume = getVarNumeric(MYSID, "DefaultVolume", 0, masterID)
	local defaultDevice = getVar(MYSID, "DefaultEcho", "", masterID)
	local alexaHost = getVar(MYSID, "AlexaHost", "", masterID)
	local amazonHost = getVar(MYSID, "AmazonHost", "", masterID)
	local language = getVar(MYSID, "Language", "", masterID)
	local useAnnoucements = getVarNumeric(MYSID, "UseAnnoucements", 0, masterID)

	local command = string.format(args, username, password,
										(settings.Volume or volume),
										(settings.Language or language), (settings.Language or language),
										amazonHost, alexaHost,
										useAnnoucements,
										BIN_PATH, BIN_PATH,
										(settings.Text or "Test"),
										(settings.GroupZones or defaultDevice))

	-- reset onetimepass
	setVar(MYSID, "OneTimePassCode", "", masterID)
	return command
end

function sayTTS(device, settings)
	local volume = getVarNumeric(MYSID, "DefaultVolume", "", masterID)
	local defaultDevice = getVar(MYSID, "DefaultEcho", "", masterID)
	local text = (settings.Text or "Test")

	local command = buildCommand(settings) ..
					string.format(COMMANDS_SPEAK,
                                    text,
									(settings.GroupZones or defaultDevice))


	executeCommand(command)
	D("Executing command [TTS]: %1", command)

	-- wait for the next one in queue
	local defaultBreak = getVar(MYSID, "DefaultBreak", 3, masterID)
	local useAnnoucements = getVarNumeric(MYSID, "UseAnnoucements", 0, masterID)
	local timeout = defaultBreak -- in seconds

	if useAnnoucements == 0 then
		-- wait for x seconds based on string length
		local timeout =  0.062 * string.len(text) + 1
	end

	luup.call_delay("checkQueue", timeout, device)
    D("Queue will be checked again in %1 secs", timeout)
end

function runRoutine(device, settings)
	local defaultDevice = getVar(MYSID, "DefaultEcho", "", masterID)

	local command = buildCommand(settings) ..
					string.format(COMMANDS_ROUTINE,
                                    settings.RoutineName,
									(settings.GroupZones or defaultDevice))

	executeCommand(command)
	D("Executing command [runRoutine]: %1", command)
end

function runCommand(device, settings)
	local command = buildCommand(settings) ..
					settings.Command

	executeCommand(command)
	D("Executing command [runCommand]: %1", command)
end

function setVolume(volume, device, settings)
	local defaultDevice = getVar(MYSID, "DefaultEcho", "", masterID)
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

function isFile(name)
    if type(name)~="string" then return false end
    return os.rename(name,name) and true or false
end

function setupScripts()
	D("Setup in progress")
	-- mkdir
	lfs.mkdir(BIN_PATH)

	-- download script from github
	os.execute("curl https://raw.githubusercontent.com/thorsten-gehrig/alexa-remote-control/master/" .. SCRIPT_NAME .. " > " .. BIN_PATH .. "/" .. SCRIPT_NAME)

	-- add permission using lfs
	os.execute("chmod 777 " .. BIN_PATH .. "/" .. SCRIPT_NAME)
	-- TODO: fix this and use lfs
	-- lfs.attributes(BIN_PATH .. "/alexa_remote_control.sh", {permissions = "777"})

	-- first command must be executed to create cookie and setup the environment
	executeCommand(buildCommand({}))

	D("Setup completed")
end

function startPlugin(devNum)
    masterID = devNum

    L("Plugin starting: %1 - %2", _PLUGIN_NAME, _PLUGIN_VERSION)

	-- decect OpenLuup
	for k,v in pairs(luup.devices) do
		if v.device_type == "openLuup" then
			openLuup = true
			D("Running on OpenLuup: %1", openLuup)

			BIN_PATH = "/etc/cmh-ludl/VeraAlexa"
			SCRIPT_NAME = "alexa_remote_control.sh"
		end
	end

	-- init default vars
    initVar(MYSID, "DebugMode", 0, devNum)
	initVar(MYSID, "Username", "youraccount@amazon.com", devNum)
    initVar(MYSID, "Password", "password", devNum)
	initVar(MYSID, "DefaultEcho", "Bedroom", devNum)
	initVar(MYSID, "DefaultVolume", 50, devNum)

	-- init default values for US
	initVar(MYSID, "Language", "en-us", devNum)
	initVar(MYSID, "AlexaHost", "pitangui.amazon.com", devNum)
	initVar(MYSID, "AmazonHost", "amazon.com", devNum)

	-- annoucments
	initVar(MYSID, "UseAnnoucements", "0", devNum)
	initVar(MYSID, "DefaultBreak", 3, devNum)

	-- OTP
	initVar(MYSID, "OneTimePassCode", "", devNum)

	-- categories
	if luup.attr_get("category_num", devNum) == nil then
	    luup.attr_set("category_num", "15", devNum)			-- A/V
	end

	-- currentversion
	local vers = initVar(MYSID, "CurrentVersion", "0", devNum)
	if vers ~= _PLUGIN_VERSION then
		-- new version, let's reload the script again
		setVar(HASID, "Configured", 0, devNum)
		setVar(MYSID, "CurrentVersion", _PLUGIN_VERSION, devNum)
	end
	
	-- check for configured flag and for the script
	local configured = getVarNumeric(HASID, "Configured", 0, masterID)
	if configured == 0 or not isFile(BIN_PATH .. "/" .. SCRIPT_NAME) then
		setupScripts()
		setVar(HASID, "Configured", 1, devNum)
	else
		D("Engine correctly configured: skipping config")
	end

	-- randomizer
	math.randomseed(tonumber(tostring(os.time()):reverse():sub(1,6)))

    checkQueue(masterID)

    -- status
    luup.set_failure(0, devNum)
    return true, "Ready", _PLUGIN_NAME
end
