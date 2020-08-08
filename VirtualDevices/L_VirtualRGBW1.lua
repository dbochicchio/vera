module("L_VirtualRGBW1", package.seeall)

local _PLUGIN_NAME = "VirtualRGBW"
local _PLUGIN_VERSION = "1.5.0"

local debugMode = false

local MYSID									= "urn:bochicchio-com:serviceId:VirtualRGBW1"

local BULBTYPE								= "urn:schemas-upnp-org:device:DimmableRGBLight:1"

local SWITCHSID								= "urn:upnp-org:serviceId:SwitchPower1"
local DIMMERSID								= "urn:upnp-org:serviceId:Dimming1"
local COLORSID								= "urn:micasaverde-com:serviceId:Color1"
local HASID                                 = "urn:micasaverde-com:serviceId:HaDevice1"

local COMMANDS_SETPOWER						= "SetPowerURL"
local COMMANDS_SETBRIGHTNESS				= "SetBrightnessURL"
local COMMANDS_SETRGBCOLOR					= "SetRGBColorURL"
local COMMANDS_SETWHITETEMPERATURE			= "SetWhiteTemperatureURL"
local COMMANDS_TOGGLE						= "SetToggleURL"
local DEFAULT_ENDPOINT						= "http://"

local deviceID = -1

local localColors = {} -- locally defined colors are saved here
local mfgcolor = {}

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

local function getVarNumeric(sid, name, dflt, dev)
    local s = luup.variable_get(sid, name, dev) or ""
    if s == "" then return dflt end
    s = tonumber(s)
    return (s == nil) and dflt or s
end

local function getVar(sid, name, dflt, dev)
    local s = luup.variable_get(sid, name, dev) or ""
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

local function initVar(sid, name, dflt, dev)
    local currVal = luup.variable_get(sid, name, dev)
    if currVal == nil then
        luup.variable_set(sid, name, tostring(dflt), dev)
        return tostring(dflt)
    end
    return currVal
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

local function restoreBrightness(dev)
    -- Restore brightness
    local brightness = getVarNumeric(DIMMERSID, "LoadLevelLast", 0, dev)
	local brightnessCurrent = getVarNumeric(DIMMERSID, "LoadLevelStatus", 0, dev)

    if brightness > 0 and brightnessCurrent ~= brightness then
		sendDeviceCommand(COMMANDS_SETBRIGHTNESS, {brightness}, dev)
		setVar(DIMMERSID, "LoadLevelTarget", brightness, dev)
		setVar(DIMMERSID, "LoadLevelStatus", brightness, dev)
		setVar(DIMMERSID, "LoadLevelLast", brightness, dev)
    end
end

function actionPower(state, dev)
    -- Switch on/off
    if type(state) == "string" then
        state = (tonumber(state) or 0) ~= 0
    elseif type(state) == "number" then
        state = state ~= 0
    end

    setVar(SWITCHSID, "Target", state and "1" or "0", dev)
    setVar(SWITCHSID, "Status", state and "1" or "0", dev)
    -- UI needs LoadLevelTarget/Status to comport with state according to Vera's rules.
    if not state then
			sendDeviceCommand(COMMANDS_SETPOWER, "off", dev)
			setVar(DIMMERSID, "LoadLevelTarget", 0, dev)
			setVar(DIMMERSID, "LoadLevelStatus", 0, dev)
    else
        sendDeviceCommand(COMMANDS_SETPOWER, "on", dev)
		restoreBrightness(dev)
    end
end

function actionBrightness(newVal, dev)
    -- Dimming level change
    newVal = tonumber(newVal) or 100
    if newVal < 0 then
        newVal = 0
    elseif newVal > 100 then
        newVal = 100
    end -- range
    if newVal > 0 then
        -- Level > 0, if light is off, turn it on.
        local status = getVarNumeric(SWITCHSID, "Status", 0, dev)
        if status == 0 then
            sendDeviceCommand(COMMANDS_SETPOWER, {"on"}, dev)
            setVar(SWITCHSID, "Target", 1, dev)
            setVar(SWITCHSID, "Status", 1, dev)
        end
        sendDeviceCommand(COMMANDS_SETBRIGHTNESS, {newVal}, dev)
    elseif getVarNumeric(DIMMERSID, "AllowZeroLevel", 0, dev) ~= 0 then
        -- Level 0 allowed as on state, just go with it.
        sendDeviceCommand(COMMANDS_SETBRIGHTNESS, {0}, dev)
    else
        -- Level 0 (not allowed as an "on" state), switch light off.
        sendDeviceCommand(COMMANDS_SETPOWER, {"off"}, dev)
        setVar(SWITCHSID, "Target", 0, dev)
        setVar(SWITCHSID, "Status", 0, dev)
    end
    setVar(DIMMERSID, "LoadLevelTarget", newVal, dev)
    setVar(DIMMERSID, "LoadLevelStatus", newVal, dev)

    if newVal > 0 then setVar(DIMMERSID, "LoadLevelLast", newVal, dev) end
end

-- Approximate RGB from color temperature. We don't both with most of the algorithm
-- linked below because the lower limit is 2000 (Vera) and the upper is 6500 (Yeelight).
-- We're also not going nuts with precision, since the only reason we're doing this is
-- to make the color spot on the UI look somewhat sensible when in temperature mode.
-- Ref: https://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
local function approximateRGB(t)
    local function bound(v)
        if v < 0 then
            v = 0
        elseif v > 255 then
            v = 255
        end
        return math.floor(v)
    end
    local r, g, b = 255
    t = t / 100
    g = bound(99.471 * math.log(t) - 161.120)
    b = bound(138.518 * math.log(t - 10) - 305.048)
    return r, g, b
end

local function decodeColor(color)
    local newColor = tostring(color or ""):lower()
    if localColors[newColor] then return localColors[newColor] end
    local name
    local mfg, num = newColor:match("^([a-z])(%d+)")
    if not mfg then mfg, name = newColor:match("^([a-z])(.*)") end
    D("decodeColor() got mfg=%1 id=%2 name=%3", mfg, num, name)
    if not mfg then return color end -- No good, just return what we got.
    local t = mfgcolor[mfg]
    if t then
        for _, v in ipairs(t) do
            if name and v.name == name then return v.rgb end
            if v.id == num then return v.rgb end
        end
    else
        L({level = 2, msg = "SetColor can't find manufacturer table for %1"},
          color)
        return false
    end
    -- No luck.
    return false
end

function actionSetColor(newVal, dev, sendToDevice)
    D("actionSetColor(%1,%2)", newVal, dev)

    local status = getVarNumeric(SWITCHSID, "Status", 0, dev)
    if status == 0 and sendToDevice then
        sendDeviceCommand(COMMANDS_SETPOWER, {"on"}, dev)
        setVar(SWITCHSID, "Target", 1, dev)
        setVar(SWITCHSID, "Status", 1, dev)
    end
    local w, c, r, g, b

    local s = split(newVal)
    if #s == 3 then
        -- R,G,B -- handle both 255,0,255 OR R255,G0,B255 value
		r = tonumber(s[1]) or tonumber(string.sub(s[1], 2))
		g = tonumber(s[2]) or tonumber(string.sub(s[2], 2))
		b = tonumber(s[3]) or tonumber(string.sub(s[3], 2))
        w, c = 0, 0
		D("RGB(%1,%2,%3)", r, g, b)
        -- local rgb = r * 65536 + g * 256 + b
		if r ~= nil and g  ~= nil and  b ~= nil and sendToDevice then
			sendDeviceCommand(COMMANDS_SETRGBCOLOR, {r, g, b}, dev)
		end

		restoreBrightness(dev)
    else
        -- Wnnn, Dnnn (color range)
        local tempMin = getVarNumeric(MYSID, "MinTemperature", 1600, dev)
        local tempMax = getVarNumeric(MYSID, "MaxTemperature", 6500, dev)
        local code, temp = newVal:upper():match("([WD])(%d+)")
        local t
        if code == "W" then
            t = tonumber(temp) or 128
            temp = 2000 + math.floor(t * 3500 / 255)
            if temp < tempMin then
                temp = tempMin
            elseif temp > tempMax then
                temp = tempMax
            end
            w = t
            c = 0
        elseif code == "D" then
            t = tonumber(temp) or 128
            temp = 5500 + math.floor(t * 3500 / 255)
            if temp < tempMin then
                temp = tempMin
            elseif temp > tempMax then
                temp = tempMax
            end
            c = t
            w = 0
        elseif code == nil then
            -- Try to evaluate as integer (2000-9000K)
            temp = tonumber(newVal) or 2700
            if temp < tempMin then
                temp = tempMin
            elseif temp > tempMax then
                temp = tempMax
            end
            if temp <= 5500 then
                if temp < 2000 then temp = 2000 end -- enforce Vera min
                w = math.floor((temp - 2000) / 3500 * 255)
                c = 0
                --targetColor = string.format("W%d", w)
            elseif temp > 5500 then
                if temp > 9000 then temp = 9000 end -- enforce Vera max
                c = math.floor((temp - 5500) / 3500 * 255)
                w = 0
                --targetColor = string.format("D%d", c)
            else
                L({
                    level = 1,
                    msg = "Unable to set color, target value %1 invalid"
                }, newVal)
                return
            end
        end

		if sendToDevice then
			sendDeviceCommand(COMMANDS_SETWHITETEMPERATURE, {temp}, dev)
		end
		restoreBrightness(dev)

        r, g, b = approximateRGB(temp)
		D("aprox RGB(%1,%2,%3)", r, g, b)
    end

	local targetColor = string.format("0=%d,1=%d,2=%d,3=%d,4=%d", w, c, r, g, b)
    setVar(COLORSID, "CurrentColor", targetColor , dev)
    setVar(COLORSID, "TargetColor", targetColor, dev)
end

-- Toggle state
function actionToggleState(devNum) sendDeviceCommand(COMMANDS_TOGGLE, nil, devNum) end

function startPlugin(devNum)
	L("Plugin starting[%3]: %1 - %2", _PLUGIN_NAME, _PLUGIN_VERSION, devNum)
	deviceID = devNum

	-- generic init
	initVar(MYSID, "DebugMode", 0, deviceID)
    initVar(SWITCHSID, "Target", "0", deviceID)
    initVar(SWITCHSID, "Status", "-1", deviceID)

    initVar(DIMMERSID, "LoadLevelTarget", "0", deviceID)
    initVar(DIMMERSID, "LoadLevelStatus", "0", deviceID)
    initVar(DIMMERSID ,"LoadLevelLast", "100", deviceID)
    initVar(DIMMERSID, "TurnOnBeforeDim", "1", deviceID)
    initVar(DIMMERSID, "AllowZeroLevel", "0", deviceID)

    initVar(COLORSID, "TargetColor", "0=51,1=0,2=0,3=0,4=0", deviceID)
    initVar(COLORSID, "CurrentColor", "", deviceID)
	initVar(COLORSID, "SupportedColors", "W,D,R,G,B", deviceID)

    -- TODO: white mode scale?
    initVar(MYSID, "MinTemperature", "2000", deviceID)
    initVar(MYSID, "MaxTemperature", "6500", deviceID)

    initVar(MYSID, COMMANDS_SETPOWER, DEFAULT_ENDPOINT, deviceID)
    initVar(MYSID, COMMANDS_SETBRIGHTNESS, DEFAULT_ENDPOINT, deviceID)
    initVar(MYSID, COMMANDS_SETWHITETEMPERATURE, DEFAULT_ENDPOINT, deviceID)
    initVar(MYSID, COMMANDS_SETRGBCOLOR, DEFAULT_ENDPOINT, deviceID)

	-- device categories
	local category_num = luup.attr_get("category_num", deviceID) or 0
	if category_num == 0 then
		luup.attr_set("category_num", "2", deviceID)
		luup.attr_set("subcategory_num", "4", deviceID)
	end
	setVar(HASID, "Configured", 1, deviceID)

    -- status
    luup.set_failure(0, deviceID)
    return true, "Ready", _PLUGIN_NAME
end