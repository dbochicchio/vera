local masterID = 301
local desc = "SmartImplant"

-- master
luup.attr_set("device_file", "D_ComboDevice1.xml", masterID)
luup.attr_set("device_json", "D_ComboDevice1.json", masterID)
luup.attr_set("device_type", "urn:schemas-micasaverde-com:device:ComboDevice:1", masterID)
luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "BasicSetCapabilities", "00=Ue1,FF=Te1,2=Ue2,1=Te2", masterID)
luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "VariablesSet", "20-IN1 mode,1d,1,21-IN2 mode,1d,1,52-IN2 value for ON,2d,1,54-IN2 value for OFF,2d,2,67-ext temp change external channel,2d,3,68-ext temp periodical report,2d,3600", masterID)
luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "MultiChCapabilities", "1,7,1,94,108,34,152,159,\n2,7,1,94,108,34,152,159,\n3,33,1,94,108,34,152,159,\n4,33,1,94,108,34,152,159,\n5,16,1,94,108,34,152,159,\n6,16,1,94,108,34,152,159,\n7,33,1,94,133,142,89,49,113,108,34,152,159\n8,33,1,94,133,142,89,49,113,108,34,152,159", masterID)
luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "AssociationSet", "1,z.7;1,z.8", masterID) -- add 1,z.9 to 11 if you have other child
luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "MultiChSensType", "m3=15,m4=15,m7=1,m8=1", masterID) -- for child 
luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "PollSettings", "0", masterID) -- polling to be enabled for temperature
luup.variable_set("urn:micasaverde-com:serviceId:HaDevice1", "ChildrenSameRoom", "0", masterID) -- if you want to freely move children in other rooms
luup.attr_set("name", (desc .. " Master"), masterID)
luup.attr_set("category_num", "11", masterID)
luup.attr_set("subcategory_num", "0", masterID)

-- children
for deviceNo, d in pairs(luup.devices) do
    local parent = d.device_num_parent or -1
    if parent == masterID then
		local altid = luup.attr_get("altid", deviceNo)
		-- fix binary sensors
		if altid == "e1" or altid == "e2" then
			luup.attr_set("device_file", "D_MotionSensor1.xml", deviceNo)
			luup.attr_set("device_json", "D_MotionSensor1.json", deviceNo)
			luup.attr_set("device_type", "urn:schemas-micasaverde-com:device:MotionSensor:1", deviceNo)
			luup.attr_set("name", (desc .. " " .. (altid == "e1" and "IN1" or "IN2")), deviceNo)
			luup.attr_set("category_num", "4", deviceNo)
			luup.attr_set("subcategory_num", "3", deviceNo)
		-- fix for temp sensors
		elseif altid == "e7" or altid == "e8" or altid == "e9" or altid == "e10" or altid == "e11" then
			luup.attr_set("device_file", "D_TemperatureSensor1.xml", deviceNo)
			luup.attr_set("device_json", "D_TemperatureSensor1.json", deviceNo)
			luup.attr_set("device_type", "urn:schemas-micasaverde-com:device:TemperatureSensor:1", deviceNo)
			luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "SensorMlScale", 1, deviceNo)
			luup.variable_set("urn:micasaverde-com:serviceId:ZWaveDevice1", "SensorMlType", 1, deviceNo)

			local name = "T #" .. tostring(tonumber(string.sub(altid, 2)) - 7)

			luup.attr_set("name", (desc .. " " .. (altid == "e7" and "Ext T" or name)), deviceNo)

			luup.attr_set("category_num", "17", deviceNo)
			luup.attr_set("subcategory_num", "0", deviceNo)

			luup.attr_set("invisible", "0", deviceNo)
		-- hide all
		elseif altid == "e3" or altid == "e4" or altid == "e5" or altid == "e6" or altid == "m15" or altid == "m1" or altid == "b10" then
			luup.attr_set("invisible", "1", deviceNo)
		end
    end
end

luup.reload() -- and a browser refresh

-- Or go to Variables and edit MultiChCapabilities to be like this:
-- 1,7,1,94,108,34,152,159,
-- 2,7,1,94,108,34,152,159,
-- 3,33,1,94,108,34,152,159,
-- 4,33,1,94,108,34,152,159,
-- 5,16,1,94,108,34,152,159,
-- 6,16,1,94,108,34,152,159,
-- 7,33,1,94,133,142,89,49,113,108,34,152,159
-- 8,33,1,94,133,142,89,49,113,108,34,152,159