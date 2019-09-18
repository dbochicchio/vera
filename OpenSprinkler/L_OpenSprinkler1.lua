module("L_OpenSprinkler1", package.seeall)

local _PLUGIN_NAME = "OpenSprinkler"
local _PLUGIN_VERSION = "0.93"

local debugMode = false
local masterID = -1
local openLuup = false

local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1

-- SIDS
local MYSID								= "urn:bochicchio-com:serviceId:OpenSprinkler1"
local SWITCHSID							= "urn:upnp-org:serviceId:SwitchPower1"
local DIMMERSID							= "urn:upnp-org:serviceId:Dimming1"
local HASID								= "urn:micasaverde-com:serviceId:HaDevice1"

-- COMMANDS
local COMMANDS_STATUS					= "jc"
local COMMANDS_ZONESTATUS				= "js"
local COMMANDS_ZONENAMES				= "jn"
local COMMANDS_PROGRAMNAMES				= "jp"
local COMMANDS_OPTIONS					= "jo"
local COMMANDS_SETPOWER_ZONE			= "cm"
local COMMANDS_SETPOWER_PROGRAM			= "mp"
local COMMANDS_CHANGEVARIABLES			= "cv"

local CHILDREN_ZONE						= "OS-%s"
local CHILDREN_PROGRAM					= "OS-P-%s"

TASK_HANDLE = nil

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

function httpGet(url)
    local ltn12 = require('ltn12')
    local http = require('socket.http')
    local https = require("ssl.https")

    local response, status, headers
    local response_body = {}

    -- Handler for HTTP or HTTPS?
    local requestor = url:lower():find("^https:") and https or http
	requestor.timeout = 5

    response, status, headers = requestor.request{
        method = "GET",
        url = url .. '&rnd=' .. tostring(math.random()),
        headers = {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Connection"] = "keep-alive"
        },
        sink = ltn12.sink.table(response_body)
    }

    L('HttpGet: %1 - %2 - %3 - %4', url, (response or ''), (status or -1), tostring(table.concat(response_body or '')))

    if status ~= nil and type(status) == "number" and tonumber(status) >= 200 and tonumber(status) < 300 then
        return true, tostring(table.concat(response_body or ''))
    else
        return false, nil
    end
end

local function setLastUpdate(devID)
    luup.variable_set(HASID, "LastUpdate", os.time(), devID)
	luup.set_failure(0, devID)
end

local function setVerboseDisplay(line1, line2, devID)
	if line1 then setVar(MYSID, "DisplayLine1", line1 or "", devID) end
	if line2 then setVar(MYSID, "DisplayLine2", line2 or "", devID) end
end

local function findChild(parentID, childID)
    for k, v in pairs(luup.devices) do
        if (v.device_num_parent == parentID) and v.id == childID then
			return k
        end
    end

    D("Cannot find child: %1 - %2", parentID, childID)
    return 0
end

function deviceMessage(devID, message, error, timeout)
	local status = error and 2 or 4
	timeout = timeout or 0
	D('deviceMessage(%1,%2,%3,%4)', devID, message, error, timeout)

	if openLuup then
		D('OpenLuup detected')
		taskHandle = luup.task(message, status, _PLUGIN_NAME, taskHandle)
		if timeout ~= 0 then
			luup.call_delay("clearMessage", timeout, "", false)
		else
			taskHandle = -1
		end
	else
		luup.device_message(devID, status, message, timeout, _PLUGIN_NAME)
	end	
end

function clearMessage()
    deviceMessage(masterID, "Clearing...", TASK_SUCCESS, 0)
end

--- ***** CUSTOM FUNCTIONS *****
local function sendDeviceCommand(cmd, params)
    D("sendDeviceCommand(%1,%2,%3)", cmd, params, masterID)
    
    local pv = {}
    if type(params) == "table" then
        for k, v in ipairs(params) do
            if type(v) == "string" then
                pv[k] = v -- string.format( "%q", v )
            else
                pv[k] = tostring(v)
            end
        end
    elseif type(params) == "string" then
        table.insert(pv, params)
    elseif params ~= nil then
        table.insert(pv, tostring(params))
    end
    local pstr = table.concat(pv, "&") or ""

    local password = getVar("Password", "", masterID, MYSID)
	local ip = luup.attr_get("ip", masterID) or ""
	D('OS Controller IP: %1', ip)

    local cmdUrl = string.format('http://%s/%s?%s&pw=%s', ip, cmd, pstr, password)
	D("sendDeviceCommand - url: %1", cmdUrl)
    if (ip ~= "") then return httpGet(cmdUrl) end

    return false, nil
end

local function discovery()
	D('Discovery in progress...')

    local child_devices = luup.chdev.start(masterID)
	local syncChildren = false

	-- zones
	D('Discovery 1/2 in progress...')
    local success, response = sendDeviceCommand(COMMANDS_ZONENAMES)
    if success then
        local jsonResponse = json.decode(response)

		if type(jsonResponse.snames) == "table" then
			-- get zones
			for zoneID, zoneName in ipairs(jsonResponse.snames) do
				D("Discovery: Zone %1 - Name: %2", zoneID, zoneName)
        
				local childID = findChild(masterID, string.format(CHILDREN_ZONE, zoneID))

				-- Set the zone name
				if childID == 0 then
					D('Device to be added')
					local initVar = string.format("%s,%s=%s\n%s,%s=%s\n%s,%s=%s\n",
											MYSID, "ZoneID", (zoneID-1),
											"", "category_num", 2,
											"", "subcategory_num", 7
											)
					luup.chdev.append(masterID, child_devices, string.format(CHILDREN_ZONE, zoneID), zoneName, "", "D_DimmableLight1.xml", "", initVar, false)
					syncChildren = true
				else
					D("Set Name for Device %3 - Zone #%1: %2", zoneID, zoneName, childID)

					local overrideName = getVarNumeric("UpdateNameFromController", 1, childID, MYSID) == 1
					local oldName =	luup.attr_get("name")
					if overrideName and oldName ~= zoneName then
						luup.attr_set('name', zoneName, childID)
						setVar(MYSID, "UpdateNameFromController", 1, childID)
					end

					setVar(MYSID, "ZoneID", (zoneID-1), childID)

					if luup.attr_get("category_num", childID) == nil then
						luup.attr_set("category_num", "2", childID)			-- Dimmer
						luup.attr_set("subcategory_num", "7", childID)		-- Water Valve
						setVar(HASID, "Configured", 1, childID)

						-- dimmers
						initVar("LoadLevelTarget", "0", childID, DIMMERSID)
						initVar("LoadLevelLast", "0", childID, DIMMERSID)
						initVar("TurnOnBeforeDim", "0", childID, DIMMERSID)
						initVar("AllowZeroLevel", "1", childID, DIMMERSID)
					end

					setLastUpdate(childID)
				end
			end
		else
			L('Discovery 1/2: nil response from controller')
		end

		D('Discovery 1/2 completed...')
    else
		deviceMessage(masterID, 'Error while discovering your controller.', true)
		L('Discovery error: %1', response)
    end

	-- programs
	D('Discovery 2/2 in progress...')
	success, response = sendDeviceCommand(COMMANDS_PROGRAMNAMES)
    if success then
        local jsonResponse = json.decode(response)
		local programs = tonumber(jsonResponse.nprogs)

		if programs>0 then
			-- get programs
			for i = 1, programs do
				local programID = i-1

				local counter = 0
				for _, _ in ipairs(jsonResponse.pd[i]) do counter = counter + 1 end

				local programName = jsonResponse.pd[i][counter] -- last element in the array

				D("Discovery: Program %1 - Name: %2 - %3", programID, programName, jsonResponse.pd[i])
        
				local childID = findChild(masterID, string.format(CHILDREN_PROGRAM, programID))

				-- Set the zone name
				if childID == 0 then
					D('Device to be added')
					luup.chdev.append(masterID, child_devices, string.format(CHILDREN_PROGRAM, programID), programName, "", "D_BinaryLight1.xml", "", "", false)

					syncChildren = true
				else
					D("Set Name for Device %3 - Program #%1: %2", programID, programName, childID)

					local overrideName = getVarNumeric("UpdateNameFromController", 1, childID, MYSID) == 1
					local oldName =	luup.attr_get("name")
					if overrideName and oldName ~= programName then
						luup.attr_set('name', programName, childID)
						setVar(MYSID, "UpdateNameFromController", 1, childID)
					end
					
					setVar(MYSID, "ProgramID", programID, childID)

					-- save program data, to stop stations when stopping the program
					local programData = jsonResponse.pd[i][counter-1] -- last-1 element in the array
					if programData ~= nil then
						D("Setting zone data: %1 - %2 - %3", childID, programID, programData)
						local programData_Zones = ""
						for i=1,#programData do
							programData_Zones = programData_Zones .. tostring(programData[i]) .. ","
						end
						setVar(MYSID, "Zones", programData_Zones, childID)
					else
						D("Setting zone data FAILED: %1 - %2", childID, programID)
					end

					if luup.attr_get("category_num", childID) == nil then
						luup.attr_set("category_num", "3", childID)			-- Switch
						luup.attr_set("subcategory_num", "7", childID)		-- Water Valve

						setVar(HASID, "Configured", 1, childID)
					end

					-- watch to turn on the valve from the master
					setLastUpdate(childID)
				end
			end
		else
			L('Discovery 2/2: no programs from controller')
		end

		D('Discovery 2/2 completed...')
    else
        deviceMessage(masterID, 'Error while discovering your controller.', true)
		L('Discovery error: %1', response)
    end

	if syncChildren then
		luup.chdev.sync(masterID, child_devices)
	end

	D('Discovery completed...')
end

function updateStatus()
	D('Update status in progress...')
    -- MAIN STATUS
    local status, response = sendDeviceCommand(COMMANDS_STATUS)
    if status then
        local jsonResponse = json.decode(response)

        -- STATUS
        local state = tonumber(jsonResponse.en)
		D('Controller status: %1, %2', state, state == 1 and "1" or "0")
        setVar(SWITCHSID, "Status", state == 1 and "1" or "0", masterID)

        -- RAIN DELAY: if 0, disable, otherwise raindelay stop time
		local rainDelay = tonumber(jsonResponse.rdst)
        setVar(MYSID, "RainDelay", rainDelay, masterID)

		-- TODO: FIX! handle local time conversion
		-- TODO: use local format for time/date format
		local rainDelayDate = os.date("%H:%M:%S (%a %d %b %Y)", jsonResponse.rdst)

		setVerboseDisplay(("Controller: " .. (state == 1 and "ready" or "disabled")),
						("RainDelay: " .. (rainDelay == 0 and "disabled" or ("enabled until " .. rainDelayDate))),
						masterID)

		-- TODO: create a virtual sensor for rain delay?
		D('Update status - Status: %1 - RainDelay: %2 - %3', state, rainDelay, rainDelayDate)

		setLastUpdate(masterID)

		-- PROGRAM STATUS
		local programs = jsonResponse.ps

		if programs ~= nil and #programs > 0 then
			for i = 2, #programs do -- ignore the program
				local programIndex = i-2
				local childID = findChild(masterID, string.format(CHILDREN_PROGRAM, programIndex))
				if childID>0 then
					D('Program Status for %1: %2', childID, programs[i][1])
	                local state = tonumber(programs[i][1] or "0") >= 1 and 1 or 0

					-- Check to see if program status changed
					local currentState = getVarNumeric("Status", 0, childID, SWITCHSID)
					if currentState ~= state then
						initVar("Target", "0", childID, SWITCHSID)
						setVar(HASID, "Configured", "1", childID)
						setVar(SWITCHSID, "Status", (state == 1) and "1" or "0", childID)

						setVerboseDisplay("Program: " .. ((state == 1) and "Running" or "Idle"), nil, childID)

						D("Update Program: %1 - Status: %2", iprogramIndex, state)
					else
						D("Update Program Skipped for #%1: %2 - Status: %3 - %4", childID, programIndex, state, currentState)
					end

					setLastUpdate(childID)
				end
			end
		else
			D('No programs defined, update skipped')
		end
    else
        --deviceMessage(masterID, 'Error while updating from your controller.', true)
		L('Update status error: %1', response)
    end

    -- ZONE STATUS
    status, response = sendDeviceCommand(COMMANDS_ZONESTATUS)
    if status then
        local jsonResponse = json.decode(response)

        local stations = tonumber(jsonResponse.nstations) or 0

        setVar(MYSID, "MaxZones", stations)
        
        for i = 1, stations do
            -- Locate the device which represents the irrigation zone
            local childID = findChild(masterID, string.format(CHILDREN_ZONE, i))

            if childID>0 then
                local state = tonumber(jsonResponse.sn[i] or "0")

                -- Check to see if zone status changed
                local currentState = getVarNumeric("Status", 0, childID, SWITCHSID)
                if currentState ~= state then
					initVar("Target", "0", childID, SWITCHSID)
					setVar(HASID, "Configured", "1", childID)

                    --initVar(SWITCHSID, "Target", (state == 1) and "1" or "0", childID)
                    setVar(SWITCHSID, "Status", (state == 1) and "1" or "0", childID)

					setVerboseDisplay("Zone: " .. ((state == 1) and "Running" or "Idle"), nil, childID)

					D("Update Zone: %1 - Status: %2", i, state)
                else
                    D("Update Zone Skipped for #%1: %2 - Status: %3 - %4", childID, i, state, currentState)
				end

				setLastUpdate(childID)
            else
				D('Zone not found: %1', i)
            end
        end
    else
        --deviceMessage(masterID, 'Error while updating your controller.', true)
		L('Zone update error: %1', response)
    end

	-- OPTIONS status
	-- TODO: call COMMANDS_OPTIONS and get wl (water level in percentage)

    -- schedule again
    local refresh = getVarNumeric("Refresh", 10, devNum, HASID)
    luup.call_timer("updateStatus", 1, tostring(refresh) .. "s", "")
end

function actionPower(state, dev)
    -- Switch on/off
    if type(state) == "string" then
        state = (tonumber(state) or 0) ~= 0
    elseif type(state) == "number" then
        state = state ~= 0
    end

--	 -- support for reverse
--	local reverse = getVarNumeric("ReverseOnOff", 0, devNum, HASID) == 1
--	if reverse and state then state = false end
--	if reverse and not state then state = true end

	local level = getVarNumeric("LoadLevelLast", 5, dev, DIMMERSID) -- in seconds

	actionPowerInternal(state, level * 60, dev)
end

function actionDimming(level, dev)
	if (dev == masterID) then return end -- no dimming on master

	level = tonumber(level or "0")

	if (level <=0) then
		level = 0
	elseif (level>=100) then
		level = 100
	end
	local state = level>0

	setVar(DIMMERSID, "LoadLevelTarget", level, dev)
    setVar(DIMMERSID, "LoadLevelLast", level, dev)
	setVar(DIMMERSID, "LoadLevelStatus", level, dev)

	actionPowerInternal(state, level * 60, dev)
end

function actionPowerInternal(state, seconds, dev)
    setVar(SWITCHSID, "Target", state and "1" or "0", dev)

	local sendCommand = true

    -- master or zone?
    local cmd = COMMANDS_SETPOWER_ZONE
	local zoneIndex = getVarNumeric("ZoneID", -1, dev, MYSID)
	local programIndex = getVarNumeric("ProgramID", -1, dev, MYSID)

	local isMaster = dev == masterID
	local isZone = zoneIndex > -1
	local isProgram = programIndex > -1

	local cmdParams = {
				"en=" .. tostring(state and "1" or "0"),	-- enable flag
				"t=" .. tostring(seconds),					-- timeout, for programs only
				"sid=" .. tostring(zoneIndex),				-- station id, for stations
				"pid=" .. tostring(programIndex),			-- program id, for programs
				"uwt=0"										-- use weather adjustment
				}

    if isMaster then
		cmd = COMMANDS_CHANGEVARIABLES
		cmdParams = {
						"en=" .. tostring(state and "1" or "0"),	-- enable flag
					}
	elseif isProgram then
		cmd = COMMANDS_SETPOWER_PROGRAM
		if not state then
			sendCommand = false

			actionPowerStopStation(dev)

			setVar(SWITCHSID, "Status", "0", dev) -- stop it in the UI
		end
	end

	D('actionPower: %1 - %2', dev, zoneIndex or programIndex or "-1")
	if sendCommand then
		local result, response = sendDeviceCommand(cmd, cmdParams)

		if result then
			setVar(SWITCHSID, "Status", state and "1" or "0", dev)
		else
			deviceMessage(dev, 'Unable to send command to controller', true)
			L('Switch power error: %1 - %2 - %3', dev, state, response)
		end
	else
		D("actionPower: Command skipped")
	end
end

function actionPowerStopStation(dev)
	local v = getVar("Zones", ",", dev, MYSID)
	D("actionPowerStopStation: %1 - %2", dev, v)
	local zones = split(v, ",")
	if zones ~= nil and #zones>0 then
		for i=1,#zones-1 do -- ignore the last one
			if zones[i] ~= nil and tonumber(zones[i])>0 then -- if value >0, then the zones is inside this program
				local childID = findChild(masterID, string.format(CHILDREN_ZONE, i))
				if childID>0 then
					D('actionPowerStopStation: stop zone %1 - device %2', i, childID)
					actionPowerInternal(false, 0, childID)
				end
			end
		end
	end
end

function actionSetRainDelay(newVal, dev)
    D("actionSetRainDelay(%1,%2)", newVal, dev)

    sendDeviceCommand(COMMANDS_CHANGEVARIABLES, {"rd=" .. tostring(newVal)}, dev)
    setVar(MYSID, "RainDelay", 1, dev)
end

-- Toggle state
function actionToggleState(devNum)
	local currentState = getVarNumeric("Status", 0, devNum, SWITCHSID) == 1
	actionPower(not currentState, devNum)
end

function startPlugin(devNum)
    masterID = devNum

    L("Plugin starting: %1 - v%2", _PLUGIN_NAME, _PLUGIN_VERSION)

	if luup.openLuup ~= nil then
		openLuup =  true
		L('Running on OpenLuup: %1', openLuup)
	end

    initVar("Target", "0", devNum, SWITCHSID)
    initVar("Status", "-1", devNum, SWITCHSID)

    initVar('DebugMode', '0', devNum, MYSID)

    initVar("Password", "a6d82bced638de3def1e9bbb4983225c", devNum, MYSID) -- opendoor
    initVar("Refresh", "15", devNum, MYSID)
    initVar("MaxZones", "32", devNum, MYSID)

	-- categories
	if luup.attr_get("category_num", devNum) == nil then
	    luup.attr_set("category_num", "3", devNum)			-- Switch
	    luup.attr_set("subcategory_num", "7", devNum)		-- Water Valve
	end

	-- IP configuration
	local ip = luup.attr_get("ip", devNum)
    -- run discovery
    if ip == nil or string.len(ip) == 0 then -- no IP = failure
        luup.set_failure(2, devNum)
        return false, "Please set controller IP adddress", _PLUGIN_NAME
    end

	math.randomseed(os.clock()*100000000000)

	-- update
	updateStatus()
    discovery()

    -- status
    luup.set_failure(0, devNum)
    return true, "Ready", _PLUGIN_NAME
end
