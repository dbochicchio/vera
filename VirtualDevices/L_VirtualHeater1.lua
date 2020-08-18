module("L_VirtualHeater1", package.seeall)

local _PLUGIN_NAME = "VirtualHeater"
local _PLUGIN_VERSION = "1.5.2"

local debugMode = false

local MYSID									= "urn:bochicchio-com:serviceId:VirtualHeater1"
local SWITCHSID								= "urn:upnp-org:serviceId:SwitchPower1"
local HVACSID								= "urn:upnp-org:serviceId:HVAC_UserOperatingMode1"
local HVACSTATESID							= "urn:micasaverde-com:serviceId:HVAC_OperatingState1"
local TEMPSETPOINTSID						= "urn:upnp-org:serviceId:TemperatureSetpoint1"
local TEMPSETPOINTSID_HEAT					= "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat"
local TEMPSENSORSSID						= "urn:upnp-org:serviceId:TemperatureSensor1"
local HASID                                 = "urn:micasaverde-com:serviceId:HaDevice1"

local COMMANDS_SETPOWER						= "SetPowerURL"
local COMMANDS_SETPOWEROFF					= "SetPowerOffURL"
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
    if (cmdUrl ~= DEFAULT_ENDPOINT) then 
		D("sendDeviceCommand-url(%1)", cmdUrl)
		return httpGet(string.format(cmdUrl, pstr))
	end

	D("sendDeviceCommand: cannot send (%1)", cmdUrl)
    return false
end

-- turn on/off compatibility
function actionPower(devNum, state)
    D("sendDeviceCommand(%1,%2)", devNum, state)

    -- Switch on/off
    if type(state) == "string" then
        state = (tonumber(state) or 0) ~= 0
    elseif type(state) == "number" then
        state = state ~= 0
    end

	-- update variables
    setVar(SWITCHSID, "Target", state and "1" or "0", devNum)
    setVar(SWITCHSID, "Status", state and "1" or "0", devNum)
	setVar(HVACSID, "ModeStatus", state and "HeatOn" or "Off", devNum)
	setVar(HVACSTATESID, "ModeState", state and "Heating" or "Idle", devNum)

	-- send command
	sendDeviceCommand(state and COMMANDS_SETPOWER or COMMANDS_SETPOWEROFF, state and "on" or "off", devNum)
end

function updateSetpointAchieved(devNum)
	local tNow = os.time()
	local modeStatus, lastChanged = getVar(HVACSID, "ModeStatus", "Off", devNum)
	local temp = getVarNumeric(TEMPSENSORSSID, "CurrentTemperature", 18, devNum)
	local targetTemp = getVarNumeric(TEMPSETPOINTSID_HEAT, "CurrentSetpoint", 18, devNum)
	
	lastChanged = lastChanged or tNow
	local achieved = (modeStatus == "HeatOn" and temp>targetTemp)

	D("updateSetpointAchieved(%1, %2, %3, %4, %5)", modeStatus, temp, targetTemp, achieved, lastChanged)

	-- TODO: implement cooldown, to prevent the device from being turned on/off too frequently
	-- TODO: implement differential temp, to prevent bouncing
	local bounceTimeoutSecs = 30 -- prevent bouncing -- TODO: make it a param
	if (tNow - lastChanged <= bounceTimeoutSecs) then
		D("updateSetpointAchieved: check for status")

		setVar(TEMPSETPOINTSID, "SetpointAchieved", achieved and "1" or "0", devNum)
		setVar(TEMPSETPOINTSID_HEAT, "SetpointAchieved", achieved and "1" or "0", devNum)

		-- turn on if setpoint is not achieved
--		if not achieved and modeStatus == "Off" then -- not heating, start it
--			L("Turning on - achieved: %1 - status: %2", achieved == 1, modeStatus)
--			actionPower(devNum, 1)
--		end

		-- setpoint achieved, turn it off
		if achieved and modeStatus ~= "Off" then -- heating, stop it
			L("Turning off - achieved: %1 - status: %2", achieved == 1, modeStatus)
			actionPower(devNum, 0)
		end
	else
		D("updateSetpointAchieved: bounced (%1, %2)", tNow - lastChanged, bounceTimeoutSecs)
	end
end

-- change setpoint
function actionSetCurrentSetpoint(devNum, newSetPoint)
	D("actionSetCurrentSetpoint(%1,%2)", devNum, newSetPoint)

	local modeStatus = getVar(HVACSID, "ModeStatus", "Off", devNum)

	if modeStatus == "Off" then
		-- on off, just ignore?
	else
		-- just set variable, watch will do the real work
		setVar(TEMPSETPOINTSID, "CurrentSetpoint", newSetPoint, devNum)
	end
end

-- set energy mode
function actionSetEnergyModeTarget(devNum, newMode)
	D("actionSetEnergyModeTarget(%1,%2)", devNum, newMode)

	 setVar(HVACSID, "EnergyModeTarget", newMode, devNum)
	 setVar(HVACSID, "EnergyModeStatus", newMode, devNum)
end

-- change mode target
function actionSetModeTarget(devNum, newMode)
	if (newMode or "") == "" then newMode = "Off" end
    D("actionSetModeTarget(%1,%2)", devNum, newMode)
    
	-- just set variable, watch will do the real work
    local updated = setVar(HVACSID, "ModeTarget", newMode, devNum, true)

	-- race condition: target is set, status is not updated
	if not updated then
		actionPower(devNum, (newMode == "Off" and "0" or "1"))
	end

    return true
end

-- Toggle state
function actionToggleState(devNum) 
	D("actionToggleState(%1)", devNum)
	local status = getVarNumeric(SWITCHSID, "Status", 0, devNum)
	actionPower(devNum, status == 1 and 0 or 1)
end

-- Watch callback
function virtualThermostatWatch(devNum, sid, var, oldVal, newVal)
    D("virtualThermostatWatch(%1,%2,%3,%4,%5)", devNum, sid, var, oldVal, newVal)
	local hasChanged = oldVal ~= newVal
	devNum = tonumber(devNum)

	if sid == HVACSID then
        if var == "ModeTarget" then
			if (newVal or "") == "" then newVal = "Off" end -- AltUI+Openluup bug
			-- no need to check is changed, because sometimes ModeTarget and ModeStatus are out of sync
			actionPower(devNum, (newVal == "Off" and "0" or "1"))
        elseif var == "ModeStatus" then
            -- nothing to to do at the moment
        end
	elseif sid == TEMPSETPOINTSID then
		if (newVal or "") ~= "" and var == "CurrentSetpoint" and hasChanged then
			setVar(TEMPSETPOINTSID_HEAT, "CurrentSetpoint", newVal, devNum) -- copy and keep it in sync
		end
    elseif sid == TEMPSETPOINTSID_HEAT then
		if (newVal or "") ~= "" and var == "CurrentSetpoint" and hasChanged then
			updateSetpointAchieved(devNum)
		end
	elseif sid == TEMPSENSORSSID then
		-- update thermostat temp from external temp sensor
		if (newVal or "") ~= "" and var == "CurrentTemperature" and hasChanged then
			if devNum ~= deviceID	then
				D("Temperature sync: %1", newVal)
				setVar(TEMPSENSORSSID, "CurrentTemperature", newVal, deviceID)
			end
			updateSetpointAchieved(devNum)
		end
    end
end

function startPlugin(devNum)
	L("Plugin starting[%3]: %1 - %2", _PLUGIN_NAME, _PLUGIN_VERSION, devNum)
	deviceID = devNum

	-- generic init
	initVar(MYSID, "DebugMode", 0, deviceID)
    initVar(SWITCHSID, "Target", "0", deviceID)
    initVar(SWITCHSID, "Status", "-1", deviceID)

	-- heater init
	initVar(HVACSID, "ModeStatus", "Off", deviceID)
	initVar(TEMPSETPOINTSID, "CurrentSetpoint", "18", deviceID)
	initVar(TEMPSETPOINTSID_HEAT, "CurrentSetpoint", "18", deviceID)
	initVar(TEMPSENSORSSID, "CurrentTemperature", "18", deviceID)
	initVar(MYSID, "TemperatureDevice", "0", deviceID)

	-- http calls init
    initVar(MYSID, COMMANDS_SETPOWER, DEFAULT_ENDPOINT, deviceID)
	initVar(MYSID, COMMANDS_SETPOWEROFF, DEFAULT_ENDPOINT, deviceID)

	-- set at first run, then make it configurable
	if luup.attr_get("category_num", deviceID) == nil then
		local category_num = 5
		luup.attr_set("category_num", category_num, deviceID) -- heater
	end

	-- set at first run, then make it configurable
	local subcategory_num = luup.attr_get("subcategory_num", deviceID) or 0
	if subcategory_num == 0 then
		luup.attr_set("subcategory_num", "2", deviceID) -- heater
	end

	-- watches
    luup.variable_watch("virtualThermostatWatch", HVACSID, "ModeTarget", deviceID)
    luup.variable_watch("virtualThermostatWatch", HVACSID, "ModeStatus", deviceID)
	luup.variable_watch("virtualThermostatWatch", TEMPSETPOINTSID, "CurrentSetpoint", deviceID)
	luup.variable_watch("virtualThermostatWatch", TEMPSETPOINTSID_HEAT, "CurrentSetpoint", deviceID)
	luup.variable_watch("virtualThermostatWatch", TEMPSENSORSSID, "CurrentTemperature", deviceID)

	-- external temp sensor
	local temperatureDeviceID = getVarNumeric(MYSID, "TemperatureDevice", 0, deviceID)
	if temperatureDeviceID>0 then
		local currentTemperature = getVarNumeric(TEMPSENSORSSID, "CurrentTemperature", 0, temperatureDeviceID)
		D("Temperature startup sync: %1 - #%2", currentTemperature, temperatureDeviceID)
		setVar(TEMPSENSORSSID, "CurrentTemperature", currentTemperature, deviceID)

		luup.variable_watch("virtualThermostatWatch", TEMPSENSORSSID, "CurrentTemperature", temperatureDeviceID)
	end

	setVar(HASID, "Configured", 1, deviceID)
	setVar(HASID, "CommFailure", 0, deviceID)

    -- status
    luup.set_failure(0, deviceID)
    return true, "Ready", _PLUGIN_NAME
end