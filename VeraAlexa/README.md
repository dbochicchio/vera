# Alexa TTS (Text-To-Speech) plug-in for Vera
This plug-in uses [Alexa remote control shell script](https://raw.githubusercontent.com/thorsten-gehrig/alexa-remote-control/master/alexa_remote_control_plain.sh) to execute TTS (Text-To-Speech) commands against your Amazon Echo.

Right now, only TTS is implemented, but any other commands can be called. This is a work in progress.

Tested with success with Vera Firmware 7.30. YMMV.
All the devices are implemented as standard Vera device types.

**This is beta software!**

If you find problem with the sh script, please refer to its author.
Due to Vera's OS limited capabilities, only accounts with MFA disabled are supported at the moment.

# Installation
To install, simply upload this files using Vera's feature (Go to *Apps*, then *Develop Apps*, then *Luup files* and select *Upload*) and then create a new device using these files.
To create a new device, got to *Apps*, then *Develop Apps*, then *Create device*.

- Device Type: *urn:dlna-org:device:DLNAMediaController:1*
- Upnp Device Filename/Device File: *D_VeraAlexa1.xml*
- Upnp Implementation Filename/Implementation file: *I_VeraAlexa1.xml*
- Parent Device: none

# Configuration
After installation, ensure to change mandatory variables under your Device, then *Advanced*, then *Variables*.
Please set Username, Password, DefaultEcho, DefaultVolume, Language and AlexaHost/AmazonHost to your settings.
Please refer to the original script instructions for more info about the correct values.

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

Language should be set globally, volume can be omitted (and *DefaultVolume* variable will be used instead), device can be omitted (and *DefaultEcho* will be used instead).

# Use in code: Volume
- urn:dlna-org:serviceId:DLNAMediaController1: Down/Up/Mute
- urn:dlna-org:serviceId:DLNAMediaController1: SetVolume (with parameter DesiredVolume and GroupZones)
- urn:micasaverde-com:serviceId:Volume1: Down/Up/Mute
- 
# OpenLuup/ALTUI
The device is working and supported under OpenLuup and ALTUI. In this case, if you're using an old version, just be sure the get the base service file from Vera (automatically done if you have the Vera Bridge installed).

# Support
If you need more help, please post it on Vera's forum and tag me (@therealdb).
