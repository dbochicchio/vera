# Alexa TTS (Text-To-Speech) plug-in for Vera
This plug-in uses [Alexa remote control shell script](https://raw.githubusercontent.com/thorsten-gehrig/alexa-remote-control/master/alexa_remote_control.sh) to execute TTS (Text-To-Speech) commands against your Amazon Echo. [More info here](https://github.com/thorsten-gehrig/alexa-remote-control/).

Right now, on Vera only TTS is implemented, but any other commands can be called.
OpenLuup supports routines as well.
This is a work in progress.

Tested with success with Vera Firmware 7.30/7.31. YMMV.
All the devices are implemented as standard Vera device types.

**This is beta software!**

If you find problem with the sh script, please refer to its author.
Due to Vera's OS limited capabilities, only accounts with MFA disabled are supported at the moment.

# Installation
To install, simply upload the files in this directory (except readme) using Vera's feature (Go to *Apps*, then *Develop Apps*, then *Luup files* and select *Upload*) and then create a new device under Vera.

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
If you don't opt it for announcements (see later), only single devices are supported. You can't sync TTS on multiple devices without announcements.

Standard DLNAMediaController1:

```
luup.call_action("urn:dlna-org:serviceId:DLNAMediaController1", 
  "Say",
  {Text="Hello from Vera Alexa", Volume=50, GroupZones="Bedroom", Repeat = 3}, 666)
```

Where *666* is your device ID, Volume is the volume (from 0 to 50) and GroupZones your Echo (case sensitive!).

Sonos plug-in endpoints:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", 
  "Say",
  {Text="Hello from Vera Alexa", Volume=50, GroupZones="Bedroom", Repeat = 3}, 666)
```

Proprietary endpoint:

```
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1", 
  "Say",
  {Text="Hello from Vera Alexa", Volume=50, GroupZones="Bedroom", Repeat = 3}, 666)
```

Language should be set globally, volume can be omitted (and *DefaultVolume* variable will be used instead), device can be omitted (and *DefaultEcho* will be used instead).
You can omit *Repeat* param and 1 will be used as default.

# Use in code: Volume
- *urn:dlna-org:serviceId:DLNAMediaController1*: *Down*/*Up*/*Mute*
- *urn:dlna-org:serviceId:DLNAMediaController1*: *SetVolume* (with parameter *DesiredVolume* and *GroupZones*)
- *urn:micasaverde-com:serviceId:Volume1*: *Down*/*Up*/*Mute*

All these actions are also offered on the proprietary service *urn:bochicchio-com:serviceId:VeraAlexa1*.

# Use in code: Reset
If you need to force a reset, just use this code:

```
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1", "Reset", {}, 666)
```
This will reset cookie, device list and download the bash script again.

# Use in code: Routines (OpenLuup only)
Routines are only supported under OpenLuup at the moment:

```
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1", 
  "RunRoutine",
  {RoutineName="YourRoutineName", GroupZones="Bedroom"}, 666)
```

# Use in code: Generic commands (OpenLuup only)
Commands are only supported under OpenLuup at the moment:

```
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1", 
  "RunCommand",
  {Command="-e weather -d 'Bedroom'"}, 666)
```

Please see https://github.com/thorsten-gehrig/alexa-remote-control/blob/master/alexa_remote_control.sh for a complete list of supported commands.

# OpenLuup/ALTUI
The device is working and supported under OpenLuup and ALTUI. In this case, if you're using an old version, just be sure the get the base service file from Vera (automatically done if you have the Vera Bridge installed).

# Problems with cookie?
Sometimes cookie will not get generated. Here's the steps to get it manually:
https://community.getvera.com/t/alexa-tts-text-to-speech-and-more-plug-in-for-vera/211033/156

# One Time Passcode
Thanks to @E1cid, One Time Passcode are now supported. This makes easy to renew a cookie when dealing with 2-factory authentication (2FA).
Amazon will send you a One Time Passwcode via e-mail or SMS. You can use tasker/automate/whatever to send text with OTP to renew cookie with 2FA.

http://*veraIP*:3480/data_request?id=variableset&DeviceNum=666&serviceId=urn:bochicchio-com:serviceId:VeraAlexa1&Variable=OneTimePassCode&Value=*OTPVALUE*

# Announcements with TTS (OpenLuup only)
You have to specifically enable announcements. This will give you the ability to have sync'ed TTS on groups (ie: Everywhere or your own defined groups).
As per Amazon docs, Alexa excludes that device from announcement delivery:
- Announcements are disabled. (To enable or disable announcements in the Alexa app, go to  **Settings → Device Settings →  *device_name*  → Communications → Announcements**.)
- The device is actively in a call or drop-in.
- The device is in Do Not Disturb mode.

*Manage Announcements in the Alexa mobile app. Go to*   **Settings > Device Settings >**   ***device_name***   **>Communications > Announcements**   *to configure settings for each Alexa device in your household.*

Announcements are opt-in and could be configured with these variables:
- UseAnnoucements: set to 1 to enable, 0 to disable
- DefaultBreak: default to 3 secs, it's the time between repeated announcements

# More code examples
```
-- routines
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1",
   "RunRoutine",
   {RoutineName="cane", GroupZone="Bedroom"}, 666)

-- any command you want
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1",
   "RunCommand",
   {Command="-e weather -d 'Bedroom'"}, 666)

-- sounds - see https://developer.amazon.com/en-US/docs/alexa/custom-skills/ask-soundlibrary.html
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1",
   "RunCommand",
   {Command="-e sound:amzn_sfx_trumpet_bugle_04 -d 'Bedroom'"}, 666) -- sounds only work on device, no groups

-- different voices, SSML - see https://developer.amazon.com/en-US/docs/alexa/custom-skills/speech-synthesis-markup-language-ssml-reference.html
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1","Say",
   {Text='<voice name="Kendra"><lang xml:lang="en-US">Hello from Vera Alexa</lang></voice>',
    Volume=50, GroupZones="Bedroom", Repeat = 3}, 666)
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1","Say",
   {Text='<voice name="Matthew"><lang xml:lang="en-US">Hello from Vera Alexa</lang></voice>',
    Volume=50, GroupZones="Bedroom", Repeat = 3}, 666)
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1","Say",
   {Text='<voice name="Amy"><lang xml:lang="en-GB">Hello from Vera Alexa</lang></voice>',
    Volume=50, GroupZones="Bedroom", Repeat = 3}, 666)

-- different language
luup.call_action("urn:bochicchio-com:serviceId:VeraAlexa1","Say",
   {Text='<voice name="Carla"><lang xml:lang="it-IT">Ciao da Vera Alexa</lang></voice>',
   Volume=50, GroupZones="Bedroom", Repeat = 3}, 666)
```

# Support
If you need more help, please post on Vera's forum and tag me (@therealdb).
https://community.getvera.com/t/alexa-tts-text-to-speech-and-more-plug-in-for-vera/211033/