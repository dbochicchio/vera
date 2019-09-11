# OpenSprinkler plug-in for Vera
Completely new and rewritten plug-in to interface an OpenSprinkler to a Vera system.
It is able to discrovery and control:
- Programs (just turn ON)
- Zones (turn on/off, length in minutes using a dimmer)
- Rain Delay (sensor coming soon)

All the devices are implemented as standard Vera device types.

**This is beta software!**

In particular, I need help with
- controller with a lot of zones (16/32+)
- controller with master valve
- controller with rain sensors
- support for scenes

# Installation
To install, simply upload this files using Vera's feature (Go to Apps, then Develop Apps, then Luup files and select upload) and then create a new device using these files.
To create a new device, got to Apps, then Develops, then Create device.
Every time you want to map a new controller, just repeat this operation.

- Upnp Device Filename/Device File: D_OpenSprinkler1.xml
- Upnp Implementation Filename/Implementation file: I_OpenSprinkler1.xml

After installation, ensure to change the "IP" variable under the master device.
Password is set, but you need to change it (see next part).
Reload your Vera's engine and wait for you zones and programs to appear.

## Variables
# For master device
- urn:bochicchio-com:serviceId:OpenSprinkler1 *DebugMode*: set to 1 to have verbose logging
- urn:bochicchio-com:serviceId:OpenSprinkler1 *Password*: set your MD5 password (default is opendoor, already setup at startup)

# For zones and programs
- urn:bochicchio-com:serviceId:OpenSprinkler1 *UpdateNameFromController*: 0 if you want to override the device name and never sync it with controller, 1 to sync it if changed (default)

### OpenLuup/ALTUI
The devices are working and supported under OpenLuup and ALTUI. In this case, just be sure the get the base service file from Vera (automatic if you have the Vera Bridge installed).

### Support
If you need more help, please post it on Vera's forum and tag me (@therealdb).