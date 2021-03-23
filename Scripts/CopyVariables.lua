-- put this in your startup code or in a function, and call it
-- this will copy tripped variable from master to child, everytime it's changed
-- 2021 Daniele Bochicchio https://github.com/dbochicchio/Vera

devices = {
	[61] = {sensorID = 89},
	[65] = {sensorID = 94},
	[63] = {sensorID = 95}
}

function copyVariable(dev_id, service, variable, oldValue, newValue)
	if tonumber(oldValue) ~= tonumber(newValue) then
		luup.log(string.format("Setting %s - %s for #%s to %s", service, variable, tostring(deviceID), tostring(newValue)))

		local deviceID = devices[dev_id].sensorID
		luup.variable_set(service, variable, newValue, deviceID)
	end
end

for deviceID, _ in next, devices do
	luup.variable_watch("copyVariable", "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", deviceID)
end