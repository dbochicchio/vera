# How to use a library via your startup code

If you want to avoid writing a lot of scenes, a custom library is the way to go. This will work well when invoked from the outside (via HTTP, so, no triggers).

Just add your code to *VeraScenes.lua* provide here. Remember to leave all your functions as public, if you want to call them.

In your startup code, just register the library:

```
VeraScenes = require("VeraScenes")
```

Then, when referring to the functions container in VeraScenes, just use this:

```
VeraScenes.turnLightsOff()
```

This could be used via HTTP calls as well (via *RunLua*):

```
http://ip-address:3480/data_request?id=lu_action&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=RunLua&Code=VeraScenes.turnLightsOn%28nil%29
```

> NB: Be sure to encode your code via an online tool such as https://www.urlencoder.org/.