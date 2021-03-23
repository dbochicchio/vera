-- Run this scripts to stabilize your Vera
-- Carefully read each one before executing it

-- 2018/2021 Daniele Bochicchio https://github.com/dbochicchio/Vera

-- 7.31 --	poll OFF for battery devices
luup.log('Poll OFF for battery devices: start')

for k, v in pairs(luup.devices) do
	local var = luup.variable_get("urn:micasaverde-com:serviceId:ZWaveDevice1", "PollSettings",k)
	local bat = luup.variable_get("urn:micasaverde-com:serviceId:HaDevice1", "BatteryLevel",k)
	if var ~= nil and v.device_num_parent== 1 and bat == nil then
		if tonumber(var) ~= 0 then
			luup.log('Poll disabled for #' .. tostring(k) .. ' - old val: ' .. tostring(var))
			luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "PollSettings", "0", k)
			luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "PollNoReply", "0", k)
		end
	end
end
luup.log('Poll OFF for battery devices: end')

-- 7.31 -- disable nightly heal (suggested for stable Zwave networks)
luup.attr_set("EnableNightlyHeal", 0, 0)

-- 7.31 --	disable wake up interval
luup.log('disable wake up interval: start')
for k, v in pairs(luup.devices) do
	local var = luup.variable_get("urn:micasaverde-com:serviceId:ZWaveDevice1", "WakeupInterval",k)
	if var ~= nil and var ~= 0 and v.device_num_parent== 1 then 
		luup.log('wake up interval disabled: #' .. tostring(k))
		luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "DisableWakeupARR_NNU", "1", k)
	end
end
luup.log('disable wake up interval: end')

-- 7.32 -- disable children delete on reconfigure
luup.log('disable children delete on reconfigure: start')
for k, v in pairs(luup.devices) do
	local var= luup.variable_get("urn:micasaverde-com:serviceId:HaDevice1", "ChildrenSameRoom", k)
	if var ~= nil and v.device_num_parent == 1 then -- zwave devices with children only
		luup.log('children delete on reconfigure disabled: #' .. tostring(k))
		luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "DeleteChildrenOnReconfigure", "0", k)
	end
end
luup.log('disable children delete on reconfigure: end')