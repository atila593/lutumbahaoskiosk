#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.2.1-firefox-fixed"

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting Firefox HAOSKiosk ########"
bashio::log.info "$(date) [Version: $VERSION]"
bashio::log.info "$(uname -a)"

ha_info=$(bashio::info)
bashio::log.info "Core=$(echo "$ha_info" | jq -r '.homeassistant')  HAOS=$(echo "$ha_info" | jq -r '.hassos')  MACHINE=$(echo "$ha_info" | jq -r '.machine')  ARCH=$(echo "$ha_info" | jq -r '.arch')"

ONBOARD_CONFIG_FILE="/config/onboard-settings.dconf"

# ------------------- CLEANUP ON EXIT -------------------
cleanup() {
    local exit_code=$?
    if [ "${SAVE_ONSCREEN_CONFIG:-false}" = "true" ] && [ -f "$ONBOARD_CONFIG_FILE" ]; then
        dconf dump /org/onboard/ > "$ONBOARD_CONFIG_FILE" 2>/dev/null || true
    fi
    jobs -p | xargs -r kill 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

# ------------------- LOAD CONFIG -------------------
load_config_var() {
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local MASK="${3:-}"
    local VALUE=""
    
    if declare -p "$VAR_NAME" >/dev/null 2>&1; then
        VALUE="${!VAR_NAME}"
    elif bashio::config.exists "${VAR_NAME,,}"; then
        VALUE="$(bashio::config "${VAR_NAME,,}")"
    else
        bashio::log.warning "Unknown config key: ${VAR_NAME,,}"
        VALUE=""
    fi

    if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
        bashio::log.warning "Config key '${VAR_NAME,,}' unset, setting to default: '$DEFAULT'"
        VALUE="$DEFAULT"
    fi

    printf -v "$VAR_NAME" '%s' "$VALUE"
    eval "export $VAR_NAME"

    if [ -z "$MASK" ]; then
        bashio::log.info "$VAR_NAME=$VALUE"
    else
        bashio::log.info "$VAR_NAME=XXXXXX"
    fi
}

# ------------------- CONFIG VARIABLES -------------------
load_config_var HA_USERNAME
load_config_var HA_PASSWORD "" 1
load_config_var HA_URL "http://localhost:8123"
load_config_var HA_DASHBOARD ""
load_config_var LOGIN_DELAY 1.0
load_config_var ZOOM_LEVEL 100
load_config_var BROWSER_REFRESH 600
load_config_var SCREEN_TIMEOUT 600
load_config_var OUTPUT_NUMBER 1
load_config_var DARK_MODE true
load_config_var HA_SIDEBAR "none"
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var CURSOR_TIMEOUT 5
load_config_var KEYBOARD_LAYOUT us
load_config_var ONSCREEN_KEYBOARD false
load_config_var SAVE_ONSCREEN_CONFIG true
load_config_var XORG_CONF ""
load_config_var XORG_APPEND_REPLACE append
load_config_var REST_PORT 8080
load_config_var REST_AUTHORIZATION_TOKEN "" 1
load_config_var ALLOW_USER_COMMANDS false
[ "$ALLOW_USER_COMMANDS" = "true" ] && bashio::log.warning "WARNING: 'allow_user_commands' set to 'true'"
load_config_var DEBUG_MODE false

if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.error "Error: HA_USERNAME and HA_PASSWORD must be set"
    exit 1
fi

# ------------------- START DBUS -------------------
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
export DBUS_SESSION_BUS_ADDRESS
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bashio::log.warning "WARNING: Failed to start dbus-daemon"
else
    bashio::log.info "DBus started with: DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
    echo "export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'" >> "$HOME/.profile"
fi

# ------------------- HANDLE /dev/tty0 -------------------
if [ -e "/dev/tty0" ]; then
    bashio::log.info "/dev/tty0 exists, attempting to make it accessible..."
    chmod 666 /dev/tty0 2>/dev/null || true
fi

# ------------------- START UDEV -------------------
bashio::log.info "Starting 'udevd' and (re-)triggering..."
udevd --daemon 2>/dev/null || true
udevadm trigger 2>/dev/null || true

# ------------------- DRM VIDEO CARDS -------------------
bashio::log.info "DRM video cards:"
find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null | sed 's/^/  /'
bashio::log.info "DRM video card driver and connection status:"
selected_card=""
for status_path in /sys/class/drm/card[0-9]*-*/status; do
    [ -e "$status_path" ] || continue
    status=$(cat "$status_path")
    card_port=$(basename "$(dirname "$status_path")")
    card=${card_port%%-*}
    driver=$(basename "$(readlink "/sys/class/drm/$card/device/driver")")
    if [ -z "$selected_card" ] && [ "$status" = "connected" ]; then
        selected_card="$card"
        printf "  *"
    else
        printf "  "
    fi
    printf "%-25s%-20s%s\n" "$card_port" "$driver" "$status"
done
if [ -z "$selected_card" ]; then
    bashio::log.error "ERROR: No connected video card detected. Exiting.."
    exit 1
fi

# ------------------- XORG CONFIG -------------------
rm -rf /tmp/.X*-lock /tmp/.X11-unix 2>/dev/null || true
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

if [[ -n "$XORG_CONF" && "${XORG_APPEND_REPLACE}" = "replace" ]]; then
    bashio::log.info "Replacing default 'xorg.conf'..."
    echo "${XORG_CONF}" >| /etc/X11/xorg.conf
else
    if [ -f /etc/X11/xorg.conf.default ]; then
        cp -a /etc/X11/xorg.conf{.default,}
    else
        bashio::log.warning "/etc/X11/xorg.conf.default not found, creating empty xorg.conf"
        touch /etc/X11/xorg.conf
    fi

    # FORCE INTEL DRIVER
    if ! grep -q "Driver \"intel\"" /etc/X11/xorg.conf; then
        bashio::log.info "Overriding default 'modesetting' with 'intel' driver for Intel i915 chip."
        sed -i 's/Driver "modesetting"/Driver "intel"/' /etc/X11/xorg.conf
        sed -i '/Option "AccelMethod"/d' /etc/X11/xorg.conf
    fi

    sed -i "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\  Option        \t\t\"kmsdev\" \"/dev/dri/$selected_card\"" /etc/X11/xorg.conf
    if [ -n "$XORG_CONF" ] && [ "${XORG_APPEND_REPLACE}" = "append" ]; then
        bashio::log.info "Appending user 'xorg.conf'..."
        echo -e "\n#\n${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
fi

# ------------------- START XORG -------------------
bashio::log.info "Starting X on DISPLAY=:0..."
NOCURSOR=""
[ "$CURSOR_TIMEOUT" -lt 0 ] && NOCURSOR="-nocursor"

Xorg $NOCURSOR &
XORG_PID=$!
sleep 2
if ! kill -0 "$XORG_PID" 2>/dev/null; then
    bashio::log.error "Xorg process died immediately! Last 50 lines of /var/log/Xorg.0.log:"
    tail -50 /var/log/Xorg.0.log 2>/dev/null | sed 's/^/  /'
    exit 1
fi

bashio::log.info "X server started successfully (PID: $XORG_PID)"

# ------------------- PYTHON ENV (venv) -------------------
if [ -d /opt/venv ]; then
    bashio::log.info "Activating Python venv..."
    source /opt/venv/bin/activate
    pip install --upgrade pip
    pip install CherryPy
fi

# ------------------- REST SERVER -------------------
bashio::log.info "Starting HAOSKiosk REST server..."
python3 /rest_server.py &
REST_PID=$!
bashio::log.info "REST server started with PID: $REST_PID"

# ------------------- FIREFOX KIOSK -------------------
if [ "$DEBUG_MODE" != true ]; then
    FIREFOX_PROFILE="/tmp/firefox-kiosk-profile"
    rm -rf "$FIREFOX_PROFILE" 2>/dev/null
    mkdir -p "$FIREFOX_PROFILE"

    cat > "$FIREFOX_PROFILE/user.js" << EOF
// Firefox Kiosk Config
user_pref("browser.startup.homepage", "${HA_URL}/${HA_DASHBOARD}");
user_pref("browser.fullscreen.autohide", false);
EOF

    DISPLAY=:0 firefox --kiosk --new-instance --profile "$FIREFOX_PROFILE" "${HA_URL}/${HA_DASHBOARD}" &
    FIREFOX_PID=$!
    bashio::log.info "Firefox launched (PID: $FIREFOX_PID)"
fi

bashio::log.info "HAOSKiosk initialization completed."
wait
