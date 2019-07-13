# Virtual HTTP Light Devices plug-in for Vera
This plug-in intented to provide support to RGB, Dimmers and Binary Lights that performs their action using HTTP calls.

This plug-in is suitable to be used with Tasmota, Shelly or similar device. It could be used to simulate the entire set of options, still using a native interface and native services, with 100% compatibility to external plug-ins or code.

Since the code implements basic capabilities, you can use it to also add remote water valves (ie: connected to Tasmota or ESP*). Just be sure to change sub_category num to 7. [More info here.](http://wiki.micasaverde.com/index.php/Luup_Device_Categories)

Partially based with permission on [Yeelight-Vera](https://github.com/toggledbits/Yeelight-Vera) by Patrick Rigney (aka toggledbits).

# Installation
To install, simply upload this files using Vera's and then create a new device using these files.
Every time you want a virtual device, just repeat this operation.

### Dimmers
- Device File: D_DimmableLight1.xml
- Implementation file: I_VirtualBinaryLight1.xml
- 
### Switch
- Device File: D_BinaryLight1.xml
- Implementation file: I_VirtualBinaryLight1.xml

### RGB Lights
- Device File: D_DimmableRGBLight1.xml
- Implementation file: I_VirtualBinaryLight1.xml

### Configuration
Devices are auto-configured. At its first run, the code will create all the variables and set the category/sub_category numbers, for optimal compatibility._
To configure a virtual device, just enter its options, then go to variable.

#### Switch On/Off (All)
Set *SetPowerURL* variable to the corresponding HTTP call.
IE (for Tasmota): http://mydevice/cm?cmnd=Power+%s

The %s parameter will be replace with On/Off, based on the required action.

#### Toggle (All)
Set *ToggleURL* variable to the corresponding HTTP call.
IE (for Tasmota): http://mydevice/cm?cmnd=Power+Toggle

No params required.

#### Dimming (Dimmers, RGB Lights)
Set *SetBrightnessURL* variable to the corresponding HTTP call.
IE (for a custom device): http://mydevice/brigthness?v=%s

The %s parameter will be replace with the desired dimming (0/100).

#### Color (RGB Lights)
Set *SetRGBColorURL* variable to the corresponding HTTP call.
IE (for a custom device): http://mydevice/setcolor?v=%s

The %s parameter will be replace with the RBG color.

#### White Temperature (RGB Lights)
Set *SetWhiteTemperatureURL* variable to the corresponding HTTP call.
IE (for a custom device): http://mydevice/setwhitemode?v=%s

The %s parameter will be replace with temperature (from 2000 to 6500 k).

### Remarks
This integration is useful when the Vera system is the primary and only controller for your remotve lights.
It's possible to sync the status, using standard Vera calls:

http://veraip:3480/data_request?id=variableset&DeviceNum=6&serviceId=urn:micasaverde-com:serviceId:Color1&Variable=CurrentColor&Value=336699

### Support
If you need more help, please post it on Vera's forum and tag me (@therealdb).