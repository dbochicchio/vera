-- this script will help you migrate from Vera Dashboard 'My modes'
-- to code-based solutions, with 4 functions attached.
-- please create 4 function (turnOn, turnOff, arm, disarm) to execute the corresponding actions
-- output code will be written to logs
--
-- 2018/2021 Daniele Bochicchio https://github.com/dbochicchio/Vera

local function split(pString, pPattern)
		local Table = {}
		local fpat = "(.-)" .. pPattern
		local last_end = 1
		local s, e, cap = pString:find(fpat, 1)
		while s do
			if s ~= 1 or cap ~= "" then
				table.insert(Table, cap)
			end
			last_end = e + 1
			s, e, cap = pString:find(fpat, last_end)
		end

		if last_end <= #pString then
			cap = pString:sub(last_end)
			table.insert(Table, cap)
		end
	return Table
end

function decodeAction(k, var, securitySensor)
	-- A = arm
	-- F = turn off
	-- N = turn on

	local val = split(var .. ':D', ':')[2]

	local action = ''
	if val == 'A' then
		action = 'arm(' .. tostring(k) .. ')'
	elseif val == 'F' then
		action = 'turnOff(' .. tostring(k) .. ')'
	elseif val == 'N' then
		action = 'turnOn(' .. tostring(k) .. ')'
	elseif securitySensor then
		action = 'disarm(' .. tostring(k) .. ')'
	end

	return action .. ' -- ' .. luup.devices[k].description
end

local homeAction =''
local awayAction = ''
local nightAction = ''
local vacationAction = ''

for k, v in pairs(luup.devices) do
	local var= luup.variable_get("urn:micasaverde-com:serviceId:HaDevice1", "ModeSetting", k)

	if var ~= nil then 
		--<house mode>:<state>;<house mode>:<state>;...
		--If state is empty, the sensor is disarmed/bypassed.
		--If state is "A", the sensor is armed.
		--Example:
		--
		--1:;2:A;3:A;4:A
		--In Home(1) mode the sensor is disarmed;
		--in Away(2), Night(3) and Vacation(4) modes the sensor is armed.

		var = var:gsub(' ,42', '')

		if var ~= '1:;2:;3:;4:' then -- custom mode specified
			local securitySensor = luup.variable_get("urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", k)
			-- luup.log('#' .. tostring(k) .. ' - ' .. luup.devices[k].description .. ' - ' .. var .. ' - Security: ' .. tostring(securitySensor ~= nil))

			local parts = split(var, ';')
			if parts[1] ~= "1:" or securitySensor then
				homeAction = homeAction .. '\n\t' .. decodeAction(k, parts[1], securitySensor ~= nil)
			end
			if parts[2] ~= "2:" or securitySensor then
				awayAction = awayAction .. '\n\t' .. decodeAction(k, parts[2], securitySensor ~= nil)
			end
			if parts[3] ~= "3:" or securitySensor then
				nightAction = nightAction .. '\n\t' .. decodeAction(k, parts[3], securitySensor ~= nil)
			end
			if parts[4] ~= "4:" or securitySensor then
				vacationAction = vacationAction .. '\n\t' .. decodeAction(k, parts[4], securitySensor ~= nil)
			end
		end

		-- back to 'neutral' state
		luup.variable_set("urn:micasaverde-com:serviceId:HaDevice1", "ModeSetting", "1:;2:;3:;4:", k)
	end
end

luup.log(	'function onHomeActions()  ' .. homeAction .. '\nend\n' ..
			'function onAwayActions() ' .. awayAction .. '\nend\n' ..
			'function onNightActions() ' .. nightAction .. '\nend\n' ..
			'function onVacationActions() ' .. vacationAction .. '\nend\n')