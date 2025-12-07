#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.2.2-firefox-fixed"

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
    chmod 666 /dev/tty0 2>/dev/null || bashio::log.warning "Could not change /dev/tty0 permissions"
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
mkdir -p /tmp/.X11-unix /etc/X11
chmod 1777 /tmp/.X11-unix

# Créer un xorg.conf minimal si aucun n'existe
if [ ! -f /etc/X11/xorg.conf.default ]; then
    bashio::log.warning "/etc/X11/xorg.conf.default not found, creating minimal config"
    cat > /etc/X11/xorg.conf.default << 'EOFXORG'
Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0"
EndSection

Section "Device"
    Identifier     "Card0"
    Driver         "intel"
    Option         "DRI" "3"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Card0"
EndSection

Section "ServerFlags"
    Option "AutoAddDevices" "true"
    Option "AllowEmptyInput" "true"
EndSection
EOFXORG
fi

# Utiliser ou créer xorg.conf
if [[ -n "$XORG_CONF" && "${XORG_APPEND_REPLACE}" = "replace" ]]; then
    bashio::log.info "Replacing default 'xorg.conf' with user config..."
    echo "${XORG_CONF}" > /etc/X11/xorg.conf
else
    # Copier le fichier par défaut
    cp -a /etc/X11/xorg.conf.default /etc/X11/xorg.conf
    
    # Forcer le pilote intel pour i915
    if ! grep -q "Driver \"intel\"" /etc/X11/xorg.conf 2>/dev/null; then
        bashio::log.info "Setting intel driver for i915 chip..."
        sed -i 's/Driver "modesetting"/Driver "intel"/' /etc/X11/xorg.conf 2>/dev/null || true
        sed -i '/Option "AccelMethod"/d' /etc/X11/xorg.conf 2>/dev/null || true
    fi
    
    # Ajouter le kmsdev
    if grep -q "Option.*DRI.*3" /etc/X11/xorg.conf 2>/dev/null; then
        sed -i "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\  Option        \t\t\"kmsdev\" \"/dev/dri/$selected_card\"" /etc/X11/xorg.conf
    fi
    
    # Ajouter la config utilisateur si présente
    if [ -n "$XORG_CONF" ] && [ "${XORG_APPEND_REPLACE}" = "append" ]; then
        bashio::log.info "Appending user 'xorg.conf'..."
        echo -e "\n# User Configuration\n${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
fi

bashio::log.info "Final xorg.conf:"
cat /etc/X11/xorg.conf | sed 's/^/  /'

# ------------------- START XORG -------------------
export DISPLAY=:0
bashio::log.info "Starting X server on DISPLAY=$DISPLAY..."

NOCURSOR=""
[ "$CURSOR_TIMEOUT" -lt 0 ] && NOCURSOR="-nocursor"

# Lancer Xorg en arrière-plan
Xorg $NOCURSOR vt7 > /var/log/Xorg-startup.log 2>&1 &
XORG_PID=$!
bashio::log.info "Xorg launched with PID: $XORG_PID"

# Attendre que X démarre
XSTARTUP=15
bashio::log.info "Waiting for X server to be ready..."
for ((i=1; i<=XSTARTUP; i++)); do
    # Vérifier que le processus tourne
    if ! kill -0 "$XORG_PID" 2>/dev/null; then
        bashio::log.error "ERROR: Xorg process died! Logs:"
        tail -50 /var/log/Xorg.0.log 2>/dev/null | sed 's/^/  /'
        tail -20 /var/log/Xorg-startup.log 2>/dev/null | sed 's/^/  /'
        exit 1
    fi
    
    # Vérifier si X répond
    if xset q >/dev/null 2>&1; then
        bashio::log.info "✓ X server ready after $i seconds"
        break
    fi
    
    if [ $i -eq $XSTARTUP ]; then
        bashio::log.error "ERROR: X server timeout after ${XSTARTUP}s"
        exit 1
    fi
    sleep 1
done

# ------------------- WINDOW MANAGER -------------------
bashio::log.info "Starting Openbox window manager..."
openbox &
OPENBOX_PID=$!
sleep 1
if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
    bashio::log.warning "WARNING: Openbox failed to start, continuing anyway..."
else
    bashio::log.info "✓ Openbox started (PID: $OPENBOX_PID)"
fi

# ------------------- SCREEN CONFIG -------------------
xset +dpms
xset s "$SCREEN_TIMEOUT"
xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
bashio::log.info "Screen timeout: ${SCREEN_TIMEOUT}s"

# Configure outputs
readarray -t OUTPUTS < <(xrandr --query | awk '/ connected/ {print $1}')
if [ ${#OUTPUTS[@]} -eq 0 ]; then
    bashio::log.error "ERROR: No connected outputs detected"
    exit 1
fi

OUTPUT_NAME="${OUTPUTS[$((OUTPUT_NUMBER - 1))]}"
bashio::log.info "Using output: $OUTPUT_NAME"

xrandr --output "$OUTPUT_NAME" --primary --auto
if [ "$ROTATE_DISPLAY" != "normal" ]; then
    xrandr --output "$OUTPUT_NAME" --rotate "${ROTATE_DISPLAY}"
fi

# ------------------- KEYBOARD -------------------
setxkbmap "$KEYBOARD_LAYOUT"
bashio::log.info "Keyboard layout: $KEYBOARD_LAYOUT"

# ------------------- CURSOR -------------------
if [ "$CURSOR_TIMEOUT" -gt 0 ]; then
    unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout "$CURSOR_TIMEOUT" 2>/dev/null || \
    unclutter --start-hidden --fork --timeout "$CURSOR_TIMEOUT" 2>/dev/null || true
fi

# ------------------- REST SERVER -------------------
if [ -f /rest_server.py ]; then
    bashio::log.info "Starting REST server..."
    python3 /rest_server.py &
    REST_PID=$!
    bashio::log.info "✓ REST server started (PID: $REST_PID)"
fi

# ------------------- FIREFOX KIOSK -------------------
if [ "$DEBUG_MODE" = true ]; then
    bashio::log.warning "DEBUG MODE: Sleeping indefinitely (no Firefox)"
    exec sleep infinity
fi

bashio::log.info "Preparing Firefox kiosk..."
FIREFOX_PROFILE="/tmp/firefox-kiosk-profile"
rm -rf "$FIREFOX_PROFILE" 2>/dev/null
mkdir -p "$FIREFOX_PROFILE"

cat > "$FIREFOX_PROFILE/user.js" << EOF
user_pref("browser.startup.homepage", "${HA_URL}/${HA_DASHBOARD}");
user_pref("browser.fullscreen.autohide", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
EOF

FULL_URL="${HA_URL}/${HA_DASHBOARD}"
bashio::log.info "Launching Firefox to: $FULL_URL"

# Attendre un peu pour que X soit vraiment prêt
sleep 2

# Lancer Firefox
firefox --kiosk --new-instance --profile "$FIREFOX_PROFILE" "$FULL_URL" > /tmp/firefox.log 2>&1 &
FIREFOX_PID=$!
bashio::log.info "Firefox launched (PID: $FIREFOX_PID)"

# Attendre et vérifier
sleep 5
if ! kill -0 "$FIREFOX_PID" 2>/dev/null; then
    bashio::log.error "ERROR: Firefox died! Logs:"
    tail -30 /tmp/firefox.log 2>/dev/null | sed 's/^/  /'
    exit 1
fi

# Auto-login avec xdotool
if command -v xdotool >/dev/null 2>&1; then
    bashio::log.info "Waiting ${LOGIN_DELAY}s before auto-login..."
    sleep "$LOGIN_DELAY"
    
    (
        sleep 3
        WINDOW_ID=$(xdotool search --name "Firefox" 2>/dev/null | head -1)
        if [ -n "$WINDOW_ID" ]; then
            bashio::log.info "Auto-login: typing credentials..."
            xdotool windowactivate --sync "$WINDOW_ID"
            sleep 1
            xdotool type --delay 100 "$HA_USERNAME"
            xdotool key Tab
            sleep 0.5
            xdotool type --delay 100 "$HA_PASSWORD"
            sleep 0.5
            xdotool key Return
            bashio::log.info "✓ Auto-login completed"
        else
            bashio::log.warning "Firefox window not found for auto-login"
        fi
    ) &
fi

bashio::log.info "✓ HAOSKiosk initialization completed"
bashio::log.info "Firefox PID: $FIREFOX_PID | Xorg PID: $XORG_PID"

# Monitoring
while kill -0 "$FIREFOX_PID" 2>/dev/null; do
    sleep 30
done

bashio::log.error "Firefox process terminated unexpectedly!"
exit 1
