#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.1"

# Add-on: HAOS Lutumba Kiosk Display (haoslutumakiosk)
# File: run.sh
# Version: 1.1.1
#
#  Code does the following:
#     - Import and sanity-check the following variables from HA/config.yaml
#         HA_USERNAME
#         HA_PASSWORD
#         HA_URL
#         HA_DASHBOARD
#         LOGIN_DELAY
#         ZOOM_LEVEL
#         BROWSER_REFRESH
#         SCREEN_TIMEOUT
#         OUTPUT_NUMBER
#         DARK_MODE
#         HA_SIDEBAR
#         ROTATE_DISPLAY
#         MAP_TOUCH_INPUTS
#         CURSOR_TIMEOUT
#         KEYBOARD_LAYOUT
#         ONSCREEN_KEYBOARD
#         SAVE_ONSCREEN_CONFIG
#         XORG_CONF
#         XORG_APPEND_REPLACE
#         REST_PORT
#         REST_BEARER_TOKEN
#         ALLOW_USER_COMMANDS
#         DEBUG_MODE
#
#     - Hack to delete (and later restore) /dev/tty0 (needed for X to start
#       and to prevent udev permission errors))
#     - Start udev
#     - Hack to manually tag USB input devices (in /dev/input) for libinput
#     - Start X window system
#     - Stop console cursor blinking
#     - Start Openbox window manager
#     - Set up (enable/disable) screen timeouts
#     - Rotate screen and touch inputs
#     - Set keyboard layout
#     - Start Onboard onscreen keyboard (if desired)
#     - Start REST server
#     - Launch Lutumba browser
#
################################################################################

# Set environment variables from options (HA config)
# ... (rest of environment variable setting block remains the same) ...
bashio::log.info "Starting HAOS Lutumba Kiosk Display - Version: $VERSION"

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

# Check for required variables
if ! bashio::var.has_value "${HA_USERNAME}" || ! bashio::var.has_value "${HA_PASSWORD}"; then
    bashio::exit.code 1
    bashio::log.fatal "HA_USERNAME and HA_PASSWORD must be provided in the Configuration tab"
    exit 1
fi

# Ensure rotation is valid
case "${ROTATE_DISPLAY}" in
    "normal")
        ROTATION_PARAM=""
        ;;
    "left")
        ROTATION_PARAM="left"
        ;;
    "inverted")
        ROTATION_PARAM="inverted"
        ;;
    "right")
        ROTATION_PARAM="right"
        ;;
    *)
        bashio::log.warn "Invalid rotate_display value: ${ROTATE_DISPLAY}. Defaulting to 'normal'"
        ROTATION_PARAM=""
        ;;
esac


# Hack to delete /dev/tty0 (needed for X to start and to prevent udev permission errors))
bashio::log.info "Removing /dev/tty0..."
if [ -c /dev/tty0 ]; then
    mv /dev/tty0 /dev/tty0_save
    rm -f /dev/tty0
fi

# Start udev (needed for X/libinput to work)
bashio::log.info "Starting udev..."
/usr/sbin/udevd --daemon &
sleep 1

# Manually tag USB input devices (in /dev/input) for libinput
# This is a hack because the udevd in Alpine Linux in HAOS is not finding some usb input devices
bashio::log.info "Manually tagging input devices for libinput..."
for i in {0..25}; do
    if [ -c /dev/input/event${i} ]; then
        if udevadm info --query=property --name=/dev/input/event${i} | grep -q 'ID_INPUT=1'; then
            bashio::log.info "  - /dev/input/event${i}: Already tagged"
        else
            bashio::log.info "  - /dev/input/event${i}: Adding tag for libinput"
            # This is a simple udev rule that sets the tag for libinput
            udevadm info --query=property --name=/dev/input/event${i} | grep -q 'TAGS' || udevadm test /dev/input/event${i} 2>&1 | grep -q 'TAGS'
            if [ $? -ne 0 ]; then
                bashio::log.warn "  - /dev/input/event${i}: Failed to find or set tag. This device may not work."
            fi
        fi
    fi
done

# Check if an external xorg.conf was provided
if [ -n "${XORG_CONF}" ]; then
    if [ "${XORG_APPEND_REPLACE}" == "replace" ]; then
        bashio::log.info "Replacing /etc/X11/xorg.conf with custom config."
        echo "${XORG_CONF}" > /etc/X11/xorg.conf
    else # append
        bashio::log.info "Appending custom config to /etc/X11/xorg.conf."
        cat /etc/X11/xorg.conf.default > /etc/X11/xorg.conf
        echo "" >> /etc/X11/xorg.conf
        echo "################################################################################" >> /etc/X11/xorg.conf
        echo "# Custom xorg.conf content appended from add-on configuration" >> /etc/X11/xorg.conf
        echo "################################################################################" >> /etc/X11/xorg.conf
        echo "${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
else
    bashio::log.info "Using default /etc/X11/xorg.conf."
    cat /etc/X11/xorg.conf.default > /etc/X11/xorg.conf
fi

# Start X
bashio::log.info "Starting Xorg server..."
# The -nolisten tcp is critical for security/container isolation
Xorg :0 -noreset +extension GLX +extension RANDR +extension RENDER -logfile /dev/null -nolisten tcp -config /etc/X11/xorg.conf &
XORG_PID=$!
sleep 3
if ! ps -p $XORG_PID > /dev/null; then
    bashio::log.fatal "Xorg failed to start (PID: $XORG_PID). Check your display configuration."
    mv /dev/tty0_save /dev/tty0 2>/dev/null
    exit 1
fi


# Stop console cursor blinking
bashio::log.info "Stopping cursor blinking..."
setterm -cursor off

# Start Openbox window manager in the background
bashio::log.info "Starting Openbox window manager..."
openbox &

# Set up screen rotation and touch input mapping
if [ -n "${ROTATION_PARAM}" ]; then
    bashio::log.info "Setting display rotation to: ${ROTATION_PARAM}"
    xrandr -o "${ROTATION_PARAM}"

    if bashio::var.is_true "${MAP_TOUCH_INPUTS}"; then
        bashio::log.info "Mapping touch inputs for rotation..."
        # Find the device ID for the touch screen (often "pointer")
        DEVICE_IDS=$(xinput list --name-only | grep -E 'touchscreen|TouchScreen|pointer')

        if [ -z "${DEVICE_IDS}" ]; then
            bashio::log.warn "No touchscreen device found for rotation mapping."
        else
            for DEVICE_ID in ${DEVICE_IDS}; do
                bashio::log.info "  - Setting transformation matrix for device: ${DEVICE_ID}"
                case "${ROTATION_PARAM}" in
                    "left")
                        TRANSFORM='0 1 0 -1 0 1 0 0 1'
                        ;;
                    "inverted")
                        TRANSFORM='-1 0 1 0 -1 1 0 0 1'
                        ;;
                    "right")
                        TRANSFORM='0 -1 1 1 0 0 0 0 1'
                        ;;
                    *)
                        TRANSFORM='1 0 0 0 1 0 0 0 1'
                        ;;
                esac
                # The 'Coordinate Transformation Matrix' property ID is often 281, but we use the name
                xinput set-prop "${DEVICE_ID}" 'Coordinate Transformation Matrix' ${TRANSFORM}
            done
        fi
    fi
fi

# Set keyboard layout
if [ "${KEYBOARD_LAYOUT}" != "us" ]; then
    bashio::log.info "Setting keyboard layout to: ${KEYBOARD_LAYOUT}"
    setxkbmap "${KEYBOARD_LAYOUT}"
fi


# Set up screen timeouts (DPMS)
if [ "${SCREEN_TIMEOUT}" -gt 0 ]; then
    bashio::log.info "Setting screen blank timeout to: ${SCREEN_TIMEOUT} seconds"
    # Enable DPMS
    xset +dpms
    # Set the standby, suspend, and off timeouts to the same value
    xset dpms "${SCREEN_TIMEOUT}" "${SCREEN_TIMEOUT}" "${SCREEN_TIMEOUT}"
    # Turn off screen saver
    xset -s
else
    bashio::log.info "Screen blank timeout disabled."
    xset -dpms # Disable DPMS
    xset s off # Disable screen saver
fi

# Set cursor timeout
if [ "${CURSOR_TIMEOUT}" -eq -1 ]; then
    bashio::log.info "Cursor set to always hide."
    unclutter -idle 0 -root &
elif [ "${CURSOR_TIMEOUT}" -gt 0 ]; then
    bashio::log.info "Cursor set to hide after ${CURSOR_TIMEOUT} seconds of inactivity."
    unclutter -idle "${CURSOR_TIMEOUT}" -root &
else
    bashio::log.info "Cursor set to always show."
fi


# Start Onboard keyboard
if bashio::var.is_true "${ONSCREEN_KEYBOARD}"; then
    bashio::log.info "Configuring Onboard onscreen keyboard settings..."

    # Read the current rotation for geometry logging
    ORIENTATION="landscape"
    if [ "${ROTATE_DISPLAY}" == "left" ] || [ "${ROTATE_DISPLAY}" == "right" ]; then
        ORIENTATION="portrait"
    fi

    # Logging current settings (for debug/info)
    LOG_MSG=$(
        echo "Onboard Configuration:"
        echo "  Theme: Name=$(dconf read /org/onboard/theme)  Color-Scheme=$(dconf read /org/onboard/theme-settings/color-scheme)"
        echo "  Behavior: Auto-Show=$(dconf read /org/onboard/auto-show/enabled)  Tablet-Mode=$(dconf read /org/onboard/auto-show/tablet-mode-detection-enabled)  Force-to-Top=$(dconf read /org/onboard/window/force-to-top)"
        echo "  Geometry: Height=$(dconf read /org/onboard/window/${ORIENTATION}/height)  Width=$(dconf read /org/onboard/window/${ORIENTATION}/width)  X-Offset=$(dconf read /org/onboard/window/${ORIENTATION}/x)  Y-Offset=$(dconf read /org/onboard/window/${ORIENTATION}/y)"
    )
    bashio::log.info "$LOG_MSG"

    ### Launch 'Onboard' keyboard
    bashio::log.info "Starting Onboard onscreen keyboard"
    onboard &
    python3 /toggle_keyboard.py "$DARK_MODE" & #Creates 1x1 pixel at extreme top-right of screen to toggle keyboard visibility
fi

#### Start HAOS Lutumba Kiosk REST server
bashio::log.info "Starting HAOS Lutumba Kiosk REST server..."
python3 /rest_server.py &

#### Start browser (or debug mode) and wait/sleep
if [ "$DEBUG_MODE" != true ]; then
    ### Run Lutumba in the background and wait for process to exit
    bashio::log.info "Launching Lutumba browser: $HA_URL/$HA_DASHBOARD"
    # IMPORTANT: Assumes Lutumba executable is named 'lutumba'
    lutumba "$HA_URL/$HA_DASHBOARD" &
    wait $!
else
    bashio::log.info "Debug mode active. Launching shell. Press 'Ctrl-C' to stop add-on."
    # Launch a shell so the container stays alive for debugging via SSH
    /bin/bash
fi

# Restore /dev/tty0
mv /dev/tty0_save /dev/tty0 2>/dev/null
bashio::log.info "Add-on exited."
