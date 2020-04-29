# Virtual HTTP Devices plug-in for Vera
This plug-in intented to provide support for Heaters, Window Covers/Roller Shutters/Blinds, RGB(CCT), Dimmers and Binary Lights, and Sensors (Door, Leak, Motion, Smoke, CO, Glass Break, Freeze or Binary) that performs their actions using HTTP calls.

This plug-in is suitable to be used with Tasmota, Shelly or similar devices. It could be used to simulate the entire set of options, still using a native interface and native services, with 100% compatibility to external plug-ins or code.

Since the code implements basic capabilities, you can use it also to add remote water valves (ie: connected to Tasmota or ESP*). Just be sure to change sub_category num to 7. [More info here.](http://wiki.micasaverde.com/index.php/Luup_Device_Categories)

Partially based with permission on [Yeelight-Vera](https://github.com/toggledbits/Yeelight-Vera) by Patrick Rigney (aka toggledbits).

# Installation via MiOS App Store
The files are available via MiOS App Store. Plug-in ID is 9281 if you want to install it manually.
Go to your Vera web interface, then Apps, Install Apps and search for "Virtual HTTP Light Devices (Switch, Dimmer, RGB)". Click Details, then Install.

# Manual Installation
To install, simply upload the files in this directory (except readme) using Vera's feature (Go to *Apps*, then *Develop Apps*, then *Luup files* and select *Upload*) and then create a new device under Vera.
App Store is recommended.

# Create a new device
To create a new device, got to Apps, then Develops, then Create device.
Every time you want a new virtual device, just repeat this operation.
This plug-ins support different kind of virtual devices, so choose the one you want to use and follow this guide.

### Switch
- Upnp Device Filename/Device File: *D_BinaryLight1.xml*
- Upnp Implementation Filename/Implementation file: *I_VirtualBinaryLight1.xml*

### Dimmer
- Upnp Device Filename/Device File: *D_DimmableLight1.xml*
- Upnp Implementation Filename/Implementation file: *I_VirtualBinaryLight1.xml*

### RGB(CCT) Light
- Upnp Device Filename/Device File: *D_DimmableRGBLight1.xml*
- Upnp Implementation Filename/Implementation file: *I_VirtualRGBW1.xml*

### Heater
- Upnp Device Filename/Device File: *D_Heater1.xml*
- Upnp Implementation Filename/Implementation file: *I_VirtualHeater1.xml*

The device will emulate a basic Heater, and turn on or off the associated device, translating this actions to a virtual thermostat handler. Temperature setpoints are supported, but only as cosmetic feature. No action will be taken when changing setpoints.

## Sensors (Door, Leak, Motion, Smoke, CO, Glass Break, Freeze or Binary Sensor)
- Upnp Device Filename/Device File:
	|Sensor Type|Filename|Category|Subcategory|
	|---|---|---|---|
	|Door sensor|*D_DoorSensor1.xml*|4|1|
	|Leak sensor|*D_LeakSensor1.xml*|4|3|
	|Motion sensor|*D_MotionSensor1.xml*|4|3|
	|Smoke sensor|*D_SmokeSensor1.xml*|4|4|
	|CO sensor|Not supported|4|5|
	|Glass Break|*D_MotionSensor1.xml*|4|6|
	|Freeze Break|*D_FreezeSensor1.xml*|4|7|
	|Binary sensor|Not supported|4|8|
- Upnp Implementation Filename/Implementation file: *I_VirtualGenericSensor1.xml*

Subcategory number must be changed manually as [reported here](http://wiki.micasaverde.com/index.php/Luup_Device_Categories).

### Window Covers/Roller Shutters/Blinds
- Upnp Device Filename/Device File: *D_WindowCovering1.xml*
- Upnp Implementation Filename/Implementation file: *I_VirtualBinaryLight1.xml*

### Configuration
All devices are auto-configuring. At its first run, the code will create all the variables and set the category/sub_category numbers, for optimal compatibility. 
To configure a virtual device, just enter its details, then go to Advanced and select Variables tab.
In order to configure a device, you must specify its remote HTTP endpoints. Those vary depending on the device capabilities, so search for the corresponding API. As with any HTTP device, a static IP is recommended. Check your device or router for instruction on how to do that.

#### Switch On/Off (All)
To turn ON, set *SetPowerURL* variable to the corresponding HTTP call.

For Tasmota: ```http://mydevice/cm?cmnd=Power+On```

For Shelly: ```http://mydevice/relay/0?turn=on```

To turn OFF, set *SetPowerOffURL* variable to the corresponding HTTP call.

For Tasmota: ```http://mydevice/cm?cmnd=Power+Off```

For Shelly: ```http://mydevice/relay/0?turn=off```

You can also specify only *SetPowerURL*, like this: ```http://mydevice/cm?cmnd=Power+%s```
The %s parameter will be replace with On/Off (this very same case), based on the required action.

#### Toggle (All)
Set *SetToggleURL* variable to the corresponding HTTP call.

For Tasmota: ```http://mydevice/cm?cmnd=Power+Toggle```

For Shelly:``` http://mydevice/relay/0?turn=toggle```

No params required.

#### Dimming (Dimmers, RGB Lights, Window Covers/Roller Shutters/Blinds)
Set *SetBrightnessURL* variable to the corresponding HTTP call.

For a custom device: ```http://mydevice/brigthness?v=%s```

The %s parameter will be replace with the desired dimming (0/100).

#### Color (RGB Lights)
Set *SetRGBColorURL* variable to the corresponding HTTP call.

For a custom device: ```http://mydevice/setcolor?v=%s```

The %s parameter will be replace with the RBG color.

#### White Temperature (RGB Lights)
Set *SetWhiteTemperatureURL* variable to the corresponding HTTP call.

For a custom device: ```http://mydevice/setwhitemode?v=%s```

The %s parameter will be replace with temperature (from 2000 to 6500 k).

#### Sensors
Set *SetTrippedURL* variable to the corresponding HTTP call (to trip).
Set *SetUnTrippedURL* variable to the corresponding HTTP call (to untrip).
Set *SetArmedURL* variable to the corresponding HTTP call (to arm).
Set *SetUnArmedURL* variable to the corresponding HTTP call (to disarm).

For a custom device: ```http://mydevice/tripped?v=%s```

The %s parameter will be replace with status (1 for active, 0 for disabled).

Device can be armed by Vera, and tripped/untripped via HTTP with a similar URL:
```http://*veraip*/port_3480/data_request?id=variableset&DeviceNum=6&urn:micasaverde-com:serviceId:SecuritySensor1&Variable=Tripped&Value=*1*```
where value is 1 when tripped, 0 when untripped.

#### Stop (Window Covers/Roller Shutters/Blinds)
Set *SetMoveStopURL* variable to the corresponding HTTP call.

For a custom device: ```http://mydevice/stop```

No parameters are sent.

#### Ping device for status
If you want to ping a device and have its status associated to the device, you can write a simple scene like this, to be executed every *x* minutes.

```
local function ping(address)
    local returnCode = os.execute("ping -c 1 -w 2 " .. address)

    if(returnCode ~= 0) then
        returnCode = os.execute("arping -f -w 3 -I br-wan " .. address)
    end

    return tonumber(returnCode)
end

local status = ping('192.168.1.42')
luup.set_failure(status, devID)
```

Where *devID* is the device ID and *192.168.1.42* is your IP address.

### Remarks
This integration is useful when the Vera system is the primary and only controller for your remote lights.
It's possible to sync the status, using standard Vera calls. The example is for RGB:

```
http://*veraip*:3480/data_request?id=variableset&DeviceNum=6&serviceId=urn:micasaverde-com:serviceId:Color1&Variable=CurrentColor&Value=0=0,1=0,2=255,3=0,4=0
http://*veraip*/port_3480/data_request?id=variableset&DeviceNum=6&serviceId=urn:micasaverde-com:serviceId:Color1&Variable=CurrentColor&Value=0=0,1=0,2=255,3=0,4=0
```

If you cannot use a long URL like this, you can place a custom handler in your startup code:
```
 -- http://ip:3480/data_request?id=lr_updateSwitch&device=170&status=0
function lr_updateSwitch(lul_request, lul_parameters, lul_outputformat)
	local devNum = tonumber(lul_parameters["device"], 10)
	local status = tonumber(lul_parameters["status"] or "0")
	luup.variable_set("urn:upnp-org:serviceId:SwitchPower1", "Status", status or "1", devNum)
end

luup.register_handler("lr_updateSwitch", "updateSwitch")
```

This can be called with a short URL like this:
```
http://*veraip*:3480/data_request?id=lr_updateSwitch&device=214&status=0
```

This is intented to turn a switch on/off and can be adapted for other variables as well.

### OpenLuup/ALTUI
The devices are working and supported under OpenLuup and ALTUI. In this case, just be sure the get the base service file from Vera (automatic if you have the Vera Bridge installed).

### Support
If you need more help, please post on Vera's forum and tag me (@therealdb).

https://community.getvera.com/t/virtual-http-light-devices-supporting-rgb-ww-dimmers-switch-and-much-more-tasmota-esp-shelly/209297
