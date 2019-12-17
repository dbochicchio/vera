# Virtual HTTP Light Devices plug-in for Vera
This plug-in intented to provide support to RGB(CCT), Dimmers and Binary Lights that performs their actions using HTTP calls.

This plug-in is suitable to be used with Tasmota, Shelly or similar devices. It could be used to simulate the entire set of options, still using a native interface and native services, with 100% compatibility to external plug-ins or code.

Since the code implements basic capabilities, you can use it also to add remote water valves (ie: connected to Tasmota or ESP*). Just be sure to change sub_category num to 7. [More info here.](http://wiki.micasaverde.com/index.php/Luup_Device_Categories)

Partially based with permission on [Yeelight-Vera](https://github.com/toggledbits/Yeelight-Vera) by Patrick Rigney (aka toggledbits).

# Installation via MiOS App Store
The files are available via MiOS App Store. Plug-in ID is 9281 if you want to install it manually.
Go to your Vera web interface, then Apps, Install Apps and search for "Virtual HTTP Light Devices (Switch, Dimmer, RGB)". Click Details, then Install.

# Manual Installation
To install, simply upload this files using Vera's feature (Go to Apps, then Develop Apps, then Luup files and select upload) and then create a new device using these files. App Store is recommended.

# Create a new device
To create a new device, got to Apps, then Develops, then Create device.
Every time you want a new virtual device, just repeat this operation.
This plug-ins support different kind of virtual devices, so choose the one you want to use and follow this guide.

### Switch
- Upnp Device Filename/Device File: D_BinaryLight1.xml
- Upnp Implementation Filename/Implementation file: I_VirtualBinaryLight1.xml

### Dimmers
- Upnp Device Filename/Device File: D_DimmableLight1.xml
- Upnp Implementation Filename/Implementation file: I_VirtualBinaryLight1.xml

### RGB(CCT) Lights
- Upnp Device Filename/Device File: D_DimmableRGBLight1.xml
- Upnp Implementation Filename/Implementation file: I_VirtualRGBW1.xml

### Configuration
All devices are auto-configured. At its first run, the code will create all the variables and set the category/sub_category numbers, for optimal compatibility. 
To configure a virtual device, just enter its details, then go to Advanced and select Variables tab.
In order to configure a device, you must specify its remote HTTP endpoints. Those vary depending on the device capabilities, so search for the corresponding API. As with any HTTP device, a static IP is recommended. Check your device or router for instruction on how to do that.

#### Switch On/Off (All)
To turn ON, set *SetPowerURL* variable to the corresponding HTTP call.

For Tasmota: http://mydevice/cm?cmnd=Power+On

For Shelly: http://mydevice/relay/0?turn=on

To turn OFF, set *SetPowerOffURL* variable to the corresponding HTTP call.

For Tasmota: http://mydevice/cm?cmnd=Power+Off

For Shelly: http://mydevice/relay/0?turn=off

You can also specify only *SetPowerURL*, like this: http://mydevice/cm?cmnd=Power+%s
The %s parameter will be replace with On/Off (this very same case), based on the required action.

#### Toggle (All)
Set *SetToggleURL* variable to the corresponding HTTP call.

For Tasmota: http://mydevice/cm?cmnd=Power+Toggle

For Shelly: http://mydevice/relay/0?turn=toggle

No params required.

#### Dimming (Dimmers, RGB Lights)
Set *SetBrightnessURL* variable to the corresponding HTTP call.

For a custom device: http://mydevice/brigthness?v=%s

The %s parameter will be replace with the desired dimming (0/100).

#### Color (RGB Lights)
Set *SetRGBColorURL* variable to the corresponding HTTP call.

For a custom device: http://mydevice/setcolor?v=%s

The %s parameter will be replace with the RBG color.

#### White Temperature (RGB Lights)
Set *SetWhiteTemperatureURL* variable to the corresponding HTTP call.

For a custom device: http://mydevice/setwhitemode?v=%s

The %s parameter will be replace with temperature (from 2000 to 6500 k).

### Remarks
This integration is useful when the Vera system is the primary and only controller for your remote lights.
It's possible to sync the status, using standard Vera calls:

http://veraip:3480/data_request?id=variableset&DeviceNum=6&serviceId=urn:micasaverde-com:serviceId:Color1&Variable=CurrentColor&Value=0=0,1=0,2=255,3=0,4=0

### OpenLuup/ALTUI
The devices are working and supported under OpenLuup and ALTUI. In this case, just be sure the get the base service file from Vera (automatic if you have the Vera Bridge installed).

### Support
If you need more help, please post it on Vera's forum and tag me (@therealdb).

https://community.getvera.com/t/virtual-http-light-devices-supporting-rgb-ww-dimmers-switch-and-much-more-tasmota-esp-shelly/209297
