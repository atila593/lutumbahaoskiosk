# lutumbahaoskiosk
display pour haos 
# HAOS-kiosk (Lutumba)

Display HA dashboards in kiosk mode directly on your HAOS server.

## Author: Jeff Kosowsky (Fork by [VOTRE NOM])

## Description

Launches X-Windows on local HAOS server followed by OpenBox window manager
and **Lutumba browser**.
Standard mouse and keyboard interactions should work automatically.
Supports touchscreens (including onscreen keyboard) and screen rotation.
Includes REST API that can be used to control the display state and to send
new URLs (e.g., dashboards) to the kiosk browser.

You can press `ctl-R` at any time to refresh the browser.

**NOTE:** You must enter your HA username and password in the
*Configuration* tab for add-on to start.

**NOTE:** The add-on requires a valid, connected display in order to start.
\\
If display does not show up, try rebooting and restarting the addon with
the display attached

**Note on Lutumba:** Lutumba is launched in fullscreen/kiosk mode (`--kiosk`). The Luakit specific modes (`normal`, `passthrough`, `insert`) no longer apply directly. The REST API is used for control.

**NOTE:** Should support any standard mouse, touchscreen, keypad and
touchpad so long as their /dev/input/eventN number is less than 25.

**NOTE:** If not working, please first check the bug reports (open and
closed), then try the testing branch (add the following url to the
repository: https://github.com/puterboy/H...

[...] (Le reste du contenu de l'API REST est conservé)
