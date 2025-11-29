#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.2" # MISE À JOUR POUR LUTUMBA
# Import environment variables from HA's config.yaml
HA_USERNAME=$(bashio::config 'ha_username')
HA_PASSWORD=$(bashio::config 'ha_password')
HA_URL=$(bashio::config 'ha_url')
HA_DASHBOARD=$(bashio::config 'ha_dashboard')
LOGIN_DELAY=$(bashio::config 'login_delay')
ZOOM_LEVEL=$(bashio::config 'zoom_level')
BROWSER_REFRESH=$(bashio::config 'browser_refresh')
SCREEN_TIMEOUT=$(bashio::config 'screen_timeout')
OUTPUT_NUMBER=$(bashio::config 'output_number')
DARK_MODE=$(bashio::config 'dark_mode')
HA_SIDEBAR=$(bashio::config 'ha_sidebar')
ROTATE_DISPLAY=$(bashio::config 'rotate_display')
MAP_TOUCH_INPUTS=$(bashio::config 'map_touch_inputs')
CURSOR_TIMEOUT=$(bashio::config 'cursor_timeout')
KEYBOARD_LAYOUT=$(bashio::config 'keyboard_layout')
ONSCREEN_KEYBOARD=$(bashio::config 'onscreen_keyboard')
SAVE_ONSCREEN_CONFIG=$(bashio::config 'save_onscreen_config')
XORG_CONF=$(bashio::config 'xorg_conf')
XORG_APPEND_REPLACE=$(bashio::config 'xorg_append_replace')
REST_PORT=$(bashio::config 'rest_port')
REST_BEARER_TOKEN=$(bashio::config 'rest_bearer_token')
ALLOW_USER_COMMANDS=$(bashio::config 'allow_user_commands')
DEBUG_MODE=$(bashio::config 'debug_mode')

# Export to environment for use by other scripts
export HA_USERNAME
export HA_PASSWORD
export HA_URL
export HA_DASHBOARD
export LOGIN_DELAY
export ZOOM_LEVEL
export BROWSER_REFRESH
export SCREEN_TIMEOUT
export OUTPUT_NUMBER
export DARK_MODE
export HA_SIDEBAR
export ROTATE_DISPLAY
export MAP_TOUCH_INPUTS
export CURSOR_TIMEOUT
export KEYBOARD_LAYOUT
export ONSCREEN_KEYBOARD
export SAVE_ONSCREEN_CONFIG
export XORG_CONF
export XORG_APPEND_REPLACE
export REST_PORT
export REST_BEARER_TOKEN
export ALLOW_USER_COMMANDS
export DEBUG_MODE

# HACK: delete /dev/tty0 to prevent udev permission errors and allow X to start
if [ -e /dev/tty0 ]; then
    bashio::log.info "Temporarily removing /dev/tty0 to start X server."
    rm -f /dev/tty0
    export TTY0_DELETED=true
fi

# Start udev
bashio::log.info "Starting udev..."
/usr/sbin/udevd --daemon
/usr/sbin/udevadm trigger

# Hack to manually tag USB input devices (in /dev/input) for libinput
if bashio::config.true 'map_touch_inputs'; then
    bashio::log.info "Tagging input devices for libinput..."
    for i in /dev/input/event*; do
        /usr/sbin/udevadm info -a -p $(/usr/sbin/udevadm info -q path -n $i) | grep -q 'ID_INPUT_TOUCHSCREEN' || \
        /usr/sbin/udevadm info -a -p $(/usr/sbin/udevadm info -q path -n $i) | grep -q 'ID_INPUT_KEYBOARD' || \
        /usr/sbin/udevadm info -a -p $(/usr/sbin/udevadm info -q path -n $i) | grep -q 'ID_INPUT_MOUSE' || \
        /usr/sbin/udevadm info -a -p $(/usr/sbin/udevadm info -q path -n $i) | grep -q 'ID_INPUT_TOUCHPAD' || \
        /usr/sbin/udevadm info -a -p $(/usr/sbin/udevadm info -q path -n $i) | grep -q 'ID_INPUT_JOYSTICK' || \
        /usr/sbin/udevadm info -a -p $(/usr/sbin/udevadm info -q path -n $i) | grep -q 'ID_INPUT_TABLET' && \
        /usr/sbin/udevadm trigger --action=change --subsystem-match=input --attr-match='idVendor'='*' --attr-match='idProduct'='*' --property="ID_INPUT=1" --property="ID_INPUT_KEYBOARD=1" -n $i
    done
fi

# Start X window system
bashio::log.info "Starting X server on display :0..."
/usr/bin/startx -- vt$OUTPUT_NUMBER

# Stop console cursor blinking
bashio::log.info "Stopping console cursor blinking..."
setterm -cursor off

# Start Openbox window manager
bashio::log.info "Starting Openbox window manager..."
openbox &

# Restore /dev/tty0 if it was deleted
if [ "$TTY0_DELETED" = true ]; then
    bashio::log.info "Restoring /dev/tty0."
    mknod /dev/tty0 c 4 0
    rm -f /dev/tty1
fi

#### Setup screen timeouts (DPMS)
bashio::log.info "Setting display power management..."
if [ "$SCREEN_TIMEOUT" -gt 0 ]; then
    # Set display blanking/suspend/off timeout to SCREEN_TIMEOUT
    bashio::log.info "Screen will blank after $SCREEN_TIMEOUT seconds."
    xset dpms 0 0 $SCREEN_TIMEOUT
    xset +dpms
else
    # Disable display blanking
    bashio::log.info "Screen blanking disabled."
    xset -dpms
fi

#### Rotate screen
if [ "$ROTATE_DISPLAY" != "normal" ]; then
    bashio::log.info "Rotating display to: $ROTATE_DISPLAY"
    xrandr -o "$ROTATE_DISPLAY"
fi

#### Set keyboard layout
if [ -n "$KEYBOARD_LAYOUT" ]; then
    bashio::log.info "Setting keyboard layout to: $KEYBOARD_LAYOUT"
    setxkbmap "$KEYBOARD_LAYOUT"
fi

#### Set cursor timeout
if [ "$CURSOR_TIMEOUT" -ge 0 ]; then
    if [ "$CURSOR_TIMEOUT" -eq 0 ]; then
        bashio::log.info "Cursor is set to always show."
        # xsetroot -cursor_timeout 0
    elif [ "$CURSOR_TIMEOUT" -eq -1 ]; then
        bashio::log.info "Cursor is set to never show (unclutter-xfixes will hide)."
    else
        bashio::log.info "Cursor is set to hide after $CURSOR_TIMEOUT seconds."
        unclutter-xfixes -idle $CURSOR_TIMEOUT -root &
    fi
fi

#### Install custom xorg.conf if provided
if [ -n "$XORG_CONF" ]; then
    bashio::log.info "Applying custom xorg.conf via $XORG_APPEND_REPLACE method..."
    if [ "$XORG_APPEND_REPLACE" = "replace" ]; then
        echo -e "$XORG_CONF" > /etc/X11/xorg.conf.default
    else
        echo -e "\n$XORG_CONF" >> /etc/X11/xorg.conf.default
    fi
    xorg_conf_checksum=$(md5sum /etc/X11/xorg.conf.default | awk '{print $1}')
    bashio::log.info "New xorg.conf.default checksum: $xorg_conf_checksum"
fi


#### Start Onscreen keyboard if requested
if bashio::config.true 'onscreen_keyboard'; then
    # Configure onboard keyboard
    bashio::log.info "Setting Onboard keyboard configuration..."
    ORIENTATION="landscape" # Hardcoded, as screen rotation is handled by xrandr
    if bashio::config.true 'save_onscreen_config'; then
        bashio::log.info "Restoring saved Onboard configuration."
    else
        bashio::log.info "Starting with default Onboard configuration (will not save changes)."
        dconf reset -f /org/onboard/
        dconf write /org/onboard/window/${ORIENTATION}/x 0
        dconf write /org/onboard/window/${ORIENTATION}/y 0
        dconf write /org/onboard/window/${ORIENTATION}/height 250
    fi
    # Log current Onboard settings
    LOG_MSG=$(
        echo "Current Onboard settings:"
        echo "  Theme: Theme-Name=$(dconf read /org/onboard/theme)  Color-Scheme=$(dconf read /org/onboard/theme-settings/color-scheme)"
        echo "  Behavior: Auto-Show=$(dconf read /org/onboard/auto-show/enabled)  Tablet-Mode=$(dconf read /org/onboard/auto-show/tablet-mode-detection-enabled)  Force-to-Top=$(dconf read /org/onboard/window/force-to-top)"
        echo "  Geometry: Height=$(dconf read /org/onboard/window/${ORIENTATION}/height)  Width=$(dconf read /org/onboard/window/${ORIENTATION}/width)  X-Offset=$(dconf read /org/onboard/window/${ORIENTATION}/x)  Y-Offset=$(dconf read /org/onboard/window/${ORIENTATION}/y)"
    )
    bashio::log.info "$LOG_MSG"

    ### Launch 'Onboard' keyboard
    bashio::log.info "Starting Onboard onscreen keyboard"
    onboard &
    python3 /toggle_keyboard.py "$DARK_MODE" & #Creates 1x1 pixel at extreme top-right of screen to toggle keyboard visibility
fi

#### Start  HAOSKiosk REST server
bashio::log.info "Starting HAOSKiosk REST server..."
python3 /rest_server.py &

#### Start browser (or debug mode)  and wait/sleep
if [ "$DEBUG_MODE" != true ]; then
    ### Run Lutumba in the background and wait for process to exit
    bashio::log.info "Launching Lutumba browser: $HA_URL/$HA_DASHBOARD"
    # Lancement de Lutumba en mode kiosque
    lutumba --kiosk "$HA_URL/$HA_DASHBOARD" & 
else
    bashio::log.info "Starting debug mode (waiting 30 minutes for manual intervention)"
    # Start a dummy app to keep X session alive
    sleep 1800
fi


### Main process loop to keep container running
while true
do
    sleep 30
done
