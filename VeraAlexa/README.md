# Alexa TTS (Text-To-Speech) plug-in for Vera
This plug-in uses [Alexa remote control shell script](https://raw.githubusercontent.com/thorsten-gehrig/alexa-remote-control/master/alexa_remote_control_plain.sh) to execute TTS (Text-To-Speech) commands against your Amazon Echo.

Right now, only TTS is implemented, but any other commands can be called. This is a work in progress.

Tested with success with Vera Firmware 7.30. YMMV.
All the devices are implemented as standard Vera device types.

**This is beta software!**

If you find problem with the sh script, please refer to its author.
Right now, due to Vera's OS limited capabilities, only account with MFA disabled are supported.

# Installation
To install, simply upload this files using Vera's feature (Go to Apps, then Develop Apps, then Luup files and select upload) and then create a new device using these files.
To create a new device, got to Apps, then Develops, then Create device.
Every time you want to map a new controller, just repeat this operation.

- Device Type: *urn:dlna-org:device:DLNAMediaController:1*
- Upnp Device Filename/Device File: *D_VeraAlexa1.xml*
- Upnp Implementation Filename/Implementation file: *I_VeraAlexa1.xml*
- Parent Device: none

After installation, ensure to change Username, Password, DefaultEcho, DefaultVolume, Language and AlexaHost/AmazonHost to your settings. Please refer to the original script instruction for more info.

# Use in code: TTS
Standard DLNAMediaController1:

*luup.call_action("urn:dlna-org:serviceId:DLNAMediaController1", 
  "Say",
  {Text="Hello from Vera Alexa", Volume=50, GroupZones="Bedroom"}, 666)*

Where *666* is your device ID, Volume is the volume (from 0 to 50) and GroupZones your Echo (case sensitive!)

Using Sonos plug-in endpoints:

*luup.call_action("urn:micasaverde-com:serviceId:Sonos1", 
  "Say",
  {Text="Hello from Vera Alexa", Volume=50, GroupZones="Bedroom"}, 666)*

Language should be set globally, volume can be omitted (and DefaultVolume will be used), device can be omitted (and DefaultEcho will be used).

# Use in code: Volume

- urn:dlna-org:serviceId:DLNAMediaController1: Down/Up/Mute
- urn:dlna-org:serviceId:DLNAMediaController1: SetVolume (DesiredVolume, GroupZones)
- urn:micasaverde-com:serviceId:Volume1: Down/Up/Mute
- 
# OpenLuup/ALTUI
The devices are working and supported under OpenLuup and ALTUI. In this case, if you're using an old version, just be sure the get the base service file from Vera (automatically done if you have the Vera Bridge installed).

# Support
If you need more help, please post it on Vera's forum and tag me (@therealdb).
