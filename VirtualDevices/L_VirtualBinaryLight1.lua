module("L_VirtualBinaryLight1", package.seeall)

local _PLUGIN_NAME = "VirtualBinaryLight"
local _PLUGIN_VERSION = "1.5.2"

local debugMode = false
local deviceID = -1
local deviceType

local MYSID									= "urn:bochicchio-com:serviceId:VirtualBinaryLight1"
local SWITCHSID								= "urn:upnp-org:serviceId:SwitchPower1"
local DIMMERSID								= "urn:upnp-org:serviceId:Dimming1"
local HASID                                 = "urn:micasaverde-com:serviceId:HaDevice1"
local BLINDSID								= "urn:upnp-org:serviceId:WindowCovering1"

local COMMANDS_SETPOWER						= "SetPowerURL"
local COMMANDS_SETPOWEROFF					= "SetPowerOffURL"
local COMMANDS_SETBRIGHTNESS				= "SetBrightnessURL"
local COMMANDS_TOGGLE						= "SetToggleURL"
local COMMANDS_MOVESTOP						= "SetMoveStopURL"
local DEFAULT_ENDPOINT						= "http://"

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

local function getVarNumeric(sid, name, dflt, devNum)
    local s = luup.variable_get(sid, name, devNum) or ""
    if s == "" then return dflt end
    s = tonumber(s)
    return (s == nil) and dflt or s
end

local function getVar(sid, name, dflt, devNum)
    local s = luup.variable_get(sid, name, devNum) or ""
    if s == "" then return dflt end
    return (s == nil) and dflt or s
end

local function L(msg, ...) -- luacheck: ignore 212
    local str
    local level = 50
    if type(msg) == "table" then
        str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg)
        level = msg.level or level
    else
        str = (_PLUGIN_NAME .. "[" .. _PLUGIN_VERSION .. "]") .. ": " .. tostring(msg)
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

local function D(msg, ...)
    debugMode = getVarNumeric(MYSID, "DebugMode", 0, deviceID) == 1

    if debugMode then
        local t = debug.getinfo(2)
        local pfx = (_PLUGIN_NAME .. "[" .. _PLUGIN_VERSION .. "]") .. "(" .. tostring(t.name) .. "@" ..
                        tostring(t.currentline) .. ")"
        L({msg = msg, prefix = pfx}, ...)
    end
end

-- Set variable, only if value has changed.
local function setVar(sid, name, val, devNum)
    val = (val == nil) and "" or tostring(val)
    local s = luup.variable_get(sid, name, devNum) or ""
    D("setVar(%1,%2,%3,%4) old value %5", sid, name, val, devNum, s)
    if s ~= val then
        luup.variable_set(sid, name, val, devNum)
        return true, s
    end
    return false, s
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

-- Array to map, where f(elem) returns key[,value]
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

local function initVar(sid, name, dflt, devNum)
    local currVal = luup.variable_get(sid, name, devNum)
    if currVal == nil then
        luup.variable_set(sid, name, tostring(dflt), devNum)
        return tostring(dflt)
    end
    return currVal
end

function httpGet(url)
	local ltn12 = require("ltn12")
	local _, async = pcall(require, "http_async")
	local response_body = {}
	
	D("httpGet(%1)", type(async) == "table" and "async" or "sync")

	-- async
	if type(async) == "table" then
		-- Async Handler for HTTP or HTTPS
		async.request(
		{
			method = "GET",
			url = url,
			headers = {
				["Content-Type"] = "application/json; charset=utf-8",
				["Connection"] = "keep-alive"
			},
			sink = ltn12.sink.table(response_body)
		},
		function (response, status, headers, statusline)
			D("httpGet.Async(%1, %2, %3, %4)", url, (response or ""), tostring(status), tostring(table.concat(response_body or "")))
		end)

		return true, "" -- async requests are considered good unless they"re not
	else
		-- Sync Handler for HTTP or HTTPS
		local requestor = url:lower():find("^https:") and require("ssl.https") or require("socket.http")
		local response, status, headers = requestor.request{
			method = "GET",
			url = url,
			headers = {
				["Content-Type"] = "application/json; charset=utf-8",
				["Connection"] = "keep-alive"
			},
			sink = ltn12.sink.table(response_body)
		}

		D("httpGet(%1, %2, %3, %4)", url, (response or ""), tostring(status), tostring(table.concat(response_body or "")))

		if status ~= nil and type(status) == "number" and tonumber(status) >= 200 and tonumber(status) < 300 then
			return true, tostring(table.concat(response_body or ""))
		else
			return false, nil
		end
	end
end

local function sendDeviceCommand(cmd, params, devNum)
    D("sendDeviceCommand(%1,%2,%3)", cmd, params, devNum)
    
    local pv = {}
    if type(params) == "table" then
        for k, v in ipairs(params) do
            if type(v) == "string" then
                pv[k] = v
            else
                pv[k] = tostring(v)
            end
        end
    elseif type(params) == "string" then
        table.insert(pv, params)
    elseif params ~= nil then
        table.insert(pv, tostring(params))
    end
    local pstr = table.concat(pv, ",")

    local cmdUrl = getVar(MYSID, cmd, DEFAULT_ENDPOINT, devNum)
    if (cmdUrl ~= DEFAULT_ENDPOINT) then return httpGet(string.format(cmdUrl, pstr)) end

    return false
end

local function restoreBrightness(devNum)
    -- Restore brightness
    local brightness = getVarNumeric(DIMMERSID, "LoadLevelLast", 0, devNum)
	local brightnessCurrent = getVarNumeric(DIMMERSID, "LoadLevelStatus", 0, devNum)

    if brightness > 0 and brightnessCurrent ~= brightness then
		sendDeviceCommand(COMMANDS_SETBRIGHTNESS, {brightness}, devNum)
		setVar(DIMMERSID, "LoadLevelTarget", brightness, devNum)
		setVar(DIMMERSID, "LoadLevelStatus", brightness, devNum)
    end
end

function actionPower(status, devNum)
    -- Switch on/off
    if type(status) == "string" then
        status = (tonumber(status) or 0) ~= 0
    elseif type(status) == "number" then
        status = status ~= 0
    end

	-- dimmer or not?
	local isDimmer = deviceType == "D_DimmableLight1.xml"
	local isBlind = deviceType == "D_WindowCovering1.xml"

    setVar(SWITCHSID, "Target", status and "1" or "0", devNum)
    setVar(SWITCHSID, "Status", status and "1" or "0", devNum)

    -- UI needs LoadLevelTarget/Status to conform with status according to Vera's rules.
    if not status then
			sendDeviceCommand(COMMANDS_SETPOWEROFF, "off", devNum)
			if isDimmer or isBlind then
				setVar(DIMMERSID, "LoadLevelTarget", 0, devNum)
				setVar(DIMMERSID, "LoadLevelStatus", 0, devNum)
			end
    else
        sendDeviceCommand(COMMANDS_SETPOWER, "on", devNum)
		if isDimmer then
			restoreBrightness(devNum)
		end
    end
end

function actionBrightness(newVal, devNum)
	-- dimmer or not?
	local isDimmer = deviceType == "D_DimmableLight1.xml"
	local isBlind = deviceType == "D_WindowCovering1.xml"

    -- Dimming level change
    newVal = math.floor(tonumber(newVal or 100))
	
    if newVal < 0 then
        newVal = 0
    elseif newVal > 100 then
        newVal = 100
    end -- range
    if newVal > 0 then
        -- Level > 0, if light is off, turn it on.
		if isDimmer then
			local status = getVarNumeric(SWITCHSID, "Status", 0, devNum)
			if status == 0 then
				sendDeviceCommand(COMMANDS_SETPOWER, {"on"}, devNum)
				setVar(SWITCHSID, "Target", 1, devNum)
				setVar(SWITCHSID, "Status", 1, devNum)
			end
		end

        sendDeviceCommand(COMMANDS_SETBRIGHTNESS, {newVal}, devNum)
    elseif getVarNumeric(DIMMERSID, "AllowZeroLevel", 0, devNum) ~= 0 then
        -- Level 0 allowed as on status, just go with it.
        sendDeviceCommand(COMMANDS_SETBRIGHTNESS, {0}, devNum)
    else
        -- Level 0 (not allowed as an "on" status), switch light off.
        sendDeviceCommand(COMMANDS_SETPOWEROFF, {"off"}, devNum)
        setVar(SWITCHSID, "Target", 0, devNum)
        setVar(SWITCHSID, "Status", 0, devNum)
    end
    setVar(DIMMERSID, "LoadLevelTarget", newVal, devNum)
    setVar(DIMMERSID, "LoadLevelStatus", newVal, devNum)
    if newVal > 0 then setVar(DIMMERSID, "LoadLevelLast", newVal, devNum) end
end

-- Toggle state
function actionToggleState(devNum)
	local cmdUrl = getVar(MYSID, COMMANDS_TOGGLE, DEFAULT_ENDPOINT, devNum)

	local status = getVarNumeric(SWITCHSID, "Status", 0, devNum)

	if (cmdUrl == DEFAULT_ENDPOINT or cmdUrl == "") then
		-- toggle by using the current status
		actionPower(status == 1 and 0 or 1, devNum)
	else
		-- update variables
	    setVar(SWITCHSID, "Target", status == 1 and 0 or 1, devNum)
		setVar(SWITCHSID, "Status", status == 1 and 0 or 1, devNum)

		-- toggle command specifically defined
		sendDeviceCommand(COMMANDS_TOGGLE, nil, devNum)
	end
end

-- stop for blinds
function actionStop(devNum) sendDeviceCommand(COMMANDS_MOVESTOP, nil, devNum) end

function startPlugin(devNum)
    L("Plugin starting[%3]: %1 - %2", _PLUGIN_NAME, _PLUGIN_VERSION, devNum)
	deviceID = devNum

	deviceType = luup.attr_get("device_file", deviceID)

	-- generic init
	initVar(MYSID, "DebugMode", 0, deviceID)
    initVar(SWITCHSID, "Target", "0", deviceID)
    initVar(SWITCHSID, "Status", "-1", deviceID)

	-- device specific code
	if deviceType == "D_DimmableLight1.xml" then
		-- dimmer
		initVar(DIMMERSID, "LoadLevelTarget", "0", deviceID)
		initVar(DIMMERSID, "LoadLevelStatus", "0", deviceID)
		initVar(DIMMERSID, "LoadLevelLast", "100", deviceID)
		initVar(DIMMERSID, "TurnOnBeforeDim", "1", deviceID)
		initVar(DIMMERSID, "AllowZeroLevel", "0", deviceID)

		initVar(MYSID, COMMANDS_SETBRIGHTNESS, DEFAULT_ENDPOINT, deviceID)
	elseif deviceType == "D_WindowCovering1.xml" then
		-- roller shutter
		initVar(DIMMERSID, "AllowZeroLevel", "1", deviceID)
		initVar(DIMMERSID, "LoadLevelTarget", "0", deviceID)
		initVar(DIMMERSID, "LoadLevelStatus", "0", deviceID)
		initVar(DIMMERSID, "LoadLevelLast", "100", deviceID)

		initVar(MYSID, COMMANDS_SETBRIGHTNESS, DEFAULT_ENDPOINT, deviceID)
		initVar(MYSID, COMMANDS_MOVESTOP, DEFAULT_ENDPOINT, deviceID)
	else
		-- binary light
		setVar(DIMMERSID, "LoadLevelTarget", nil, deviceID)
		setVar(DIMMERSID, "LoadLevelTarget", nil, deviceID)
		setVar(DIMMERSID, "LoadLevelStatus", nil, deviceID)
		setVar(DIMMERSID, "LoadLevelLast", nil, deviceID)
		setVar(DIMMERSID, "TurnOnBeforeDim", nil, deviceID)
		setVar(DIMMERSID, "AllowZeroLevel", nil, deviceID)
		setVar(MYSID, COMMANDS_SETBRIGHTNESS, nil, deviceID)
	end

	-- normal switch
    local commandPower = initVar(MYSID, COMMANDS_SETPOWER, DEFAULT_ENDPOINT, deviceID)
	initVar(MYSID, COMMANDS_TOGGLE, DEFAULT_ENDPOINT, deviceID)

	-- upgrade code
	initVar(MYSID, COMMANDS_SETPOWEROFF, commandPower, deviceID)

	local category_num = luup.attr_get("category_num", deviceID) or 0
	-- set at first run, then make it configurable
	if category_num == 0 then
		category_num = 3
		if deviceType == "D_DimmableLight1.xml" then category_num = 2 end -- dimmer
		if deviceType == "D_WindowCovering1.xml" then category_num = 8 end -- blind

		luup.attr_set("category_num", category_num, deviceID) -- switch
	end

	-- set at first run, then make it configurable
	if tonumber(category_num or "-1") == 3 and luup.attr_get("subcategory_num", deviceID) == nil then
		luup.attr_set("subcategory_num", "3", deviceID) -- in wall switch
	end

	setVar(HASID, "Configured", 1, deviceID)
	setVar(HASID, "CommFailure", 0, deviceID)

    -- status
    luup.set_failure(0, deviceID)
    return true, "Ready", _PLUGIN_NAME
end