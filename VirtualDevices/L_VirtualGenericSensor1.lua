module("L_VirtualGenericSensor1", package.seeall)

local _PLUGIN_NAME = "VirtualGenericSensor"
local _PLUGIN_VERSION = "1.5.1"

local debugMode = false

local MYSID									= "urn:bochicchio-com:serviceId:VirtualGenericSensor1"
local SECURITYSID							= "urn:micasaverde-com:serviceId:SecuritySensor1"
local HASID                                 = "urn:micasaverde-com:serviceId:HaDevice1"

local COMMANDS_TRIPPED						= "SetTrippedURL"
local COMMANDS_UNTRIPPED					= "SetUnTrippedURL"
local COMMANDS_ARMED						= "SetArmedURL"
local COMMANDS_UNARMED						= "SetUnArmedURL"
local DEFAULT_ENDPOINT						= "http://"

local deviceID = -1

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

function deviceMessage(devNum, message, error, timeout)
	local status = error and 2 or 4
	timeout = timeout or 15
	D("deviceMessage(%1,%2,%3,%4)", devNum, message, error, timeout)
	luup.device_message(devNum, status, message, timeout, _PLUGIN_NAME)
end

function httpGet(url)
	local ltn12 = require("ltn12")
	local _, async = pcall(require, "http_async")
	local response_body = {}
	
	D("httpGet: %1", type(async) == "table" and "async" or "sync")

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
			D("httpGet.Async: %1 - %2 - %3 - %4", url, (response or ""), tostring(status), tostring(table.concat(response_body or "")))
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

		D("httpGet: %1 - %2 - %3 - %4", url, (response or ""), tostring(status), tostring(table.concat(response_body or "")))

		if status ~= nil and type(status) == "number" and tonumber(status) >= 200 and tonumber(status) < 300 then
			return true, tostring(table.concat(response_body or ""))
		else
			return false, nil
		end
	end
end

-- plugin specific code
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

-- turn on/off compatibility
function actionArmed(devNum, state)
	state = tostring(state or "0")
	
	D("actionArmed(%1,%2,%3)", devNum, state, state == "1" and COMMANDS_ARMED or COMMANDS_UNARMED)

	setVar(SECURITYSID, "Armed", state, devNum)

	-- no need to update ArmedTripped, it will be automatic

	-- send command
	sendDeviceCommand(state == "1" and COMMANDS_ARMED or COMMANDS_UNARMED, state, devNum)
end

function actionTripped(devNum, state)
	-- no need to update LastTrip, it will be automatic
	state = tostring(state or "0")

	D("actionTripped(%1,%2,%3)", devNum, state, state == "1" and COMMANDS_TRIPPED or COMMANDS_UNTRIPPED)

	-- send command
	sendDeviceCommand(state == "1" and COMMANDS_TRIPPED or COMMANDS_UNTRIPPED, state, devNum)
end

-- Watch callback
function sensorWatch(devNum, sid, var, oldVal, newVal)
    D("sensorWatch(%1,%2,%3,%4,%5)", devNum, sid, var, oldVal, newVal)

	if oldVal == newVal then return end

	if sid == SECURITYSID then
        if var == "Tripped" then
			actionTripped(devNum, newVal or "0")
        end
--    elseif sid == GENERICSENSORSID then
--		if (newVal or "") ~= "" then
--			setVar(TEMPSETPOINTSID, "CurrentSetpoint", newVal, devNum)
--		end
    end
end

function startPlugin(devNum)
	L("Plugin starting[%3]: %1 - %2", _PLUGIN_NAME, _PLUGIN_VERSION, devNum)
	deviceID = devNum

	-- generic init
	initVar(MYSID, "DebugMode", 0, deviceID)

	-- sensors init
	initVar(SECURITYSID, "Armed", "0", deviceID)
	initVar(SECURITYSID, "Tripped", "0", deviceID)

	-- http calls init
    local commandTripped = initVar(MYSID, COMMANDS_TRIPPED, DEFAULT_ENDPOINT, deviceID)
	local commandArmed = initVar(MYSID, COMMANDS_ARMED, DEFAULT_ENDPOINT, deviceID)

	-- upgrade code
	initVar(MYSID, COMMANDS_UNTRIPPED, commandTripped, deviceID)
	initVar(MYSID, COMMANDS_UNARMED, commandArmed, deviceID)

	-- set at first run, then make it configurable
	if luup.attr_get("category_num", deviceID) == nil then
		local category_num = 4
		luup.attr_set("category_num", category_num, deviceID) -- security sensor
	end

	-- set at first run, then make it configurable
	local subcategory_num = luup.attr_get("subcategory_num", deviceID) or 0
	if subcategory_num == 0 then
		luup.attr_set("subcategory_num", "1", deviceID) -- door sensor
	end

	-- watches
    luup.variable_watch("sensorWatch", SECURITYSID, "Tripped", deviceID)
	--luup.variable_watch("sensorWatch", SECURITYSID, "Armed", deviceID)

	setVar(HASID, "Configured", 1, deviceID)
	setVar(HASID, "CommFailure", 0, deviceID)

    -- status
    luup.set_failure(0, deviceID)
    return true, "Ready", _PLUGIN_NAME
end