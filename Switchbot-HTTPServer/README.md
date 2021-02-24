# SwitchBot HTTP Server

[This script](SwitchBot-Server.js) can be used to press a SwitchBot via an HTTP endpoint.

In order to install it, be sure to have node.js installed. 
After that, just copy the script into your directory, and run *npm install* to restore your packages.

If everything is OK, you can call your bot with:

http://ip:5002/?id=mac 

Where *mac* is the Mac Address of your SwitchBot, that you can get from the SwitchBot app (colon could be removed).

Your Linux box should have access to BLE. It's running OK on Windows, but it's less reliable.

The HTTP server is based on [node-switchbot](https://github.com/futomi/node-switchbot) library. Other features, as battery or support for temperature sensors/roller shutters, could be implemented.

## Use with Vera or openLuup

In order to integrate it with Vera or openLuup, just use [Virtual HTTP Devices plug-in for Vera](https://github.com/dbochicchio/vera-VirtualDevices). It can be used with virtual Switch, or Heaters.