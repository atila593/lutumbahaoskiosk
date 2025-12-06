#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.2.1-firefox-fixed"
################################################################################
# VERSION CORRIGÉE - Résolution du bug XORG_PID
################################################################################

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting Firefox HAOSKiosk ########"
bashio::log.info "$(date) [Version: $VERSION]"
bashio::log.info "$(uname -a)"
ha_info=$(bashio::info)
bashio::log.info "Core=$(echo "$ha_info" | jq -r '.homeassistant')  HAOS=$(echo "$ha_info" | jq -r '.hassos')  MACHINE=$(echo "$ha_info" | jq -r '.machine')  ARCH=$(echo "$ha_info" | jq -r '.arch')"

#### Clean up on exit:
ONBOARD_CONFIG_FILE="/config/onboard-settings.dconf"
cleanup() {
    local exit_code=$?
    if [ "${SAVE_ONSCREEN_CONFIG:-false}" = "true" ]; then
        dconf dump /org/onboard/ > "$ONBOARD_CONFIG_FILE" 2>/dev/null || true
    fi
    jobs -p | xargs -r kill 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Get config variables from HA add-on & set environment variables
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

################################################################################
#### Start Dbus
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bashio::log.warning "WARNING: Failed to start dbus-daemon"
fi
bashio::log.info "DBus started with: DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
export DBUS_SESSION_BUS_ADDRESS
echo "export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'" >> "$HOME/.profile"

#### Handle /dev/tty0
if [ -e "/dev/tty0" ]; then
    bashio::log.info "/dev/tty0 exists, attempting to make it accessible..."
    if chmod 666 /dev/tty0 2>/dev/null; then
        bashio::log.info "Changed /dev/tty0 permissions successfully..."
    else
        bashio::log.warning "Could not change /dev/tty0 permissions, continuing anyway..."
    fi
else
    bashio::log.info "/dev/tty0 does not exist, X will use alternative..."
fi

#### Start udev
bashio::log.info "Starting 'udevd' and (re-)triggering..."
if ! udevd --daemon || ! udevadm trigger; then
    bashio::log.warning "WARNING: Failed to start udevd or trigger udev, input devices may not work"
fi

echo "/dev/input event devices:"
for dev in $(find /dev/input/event* 2>/dev/null | sort -V); do
    devpath_output=$(udevadm info --query=path --name="$dev" 2>/dev/null; echo -n $?)
    return_status=${devpath_output##*$'\n'}
    [ "$return_status" -eq 0 ] || { echo "  $dev: Failed to get device path"; continue; }
    devpath=${devpath_output%$'\n'*}
    echo "  $dev: $devpath"
done

echo "libinput list-devices found:"
libinput list-devices 2>/dev/null | awk '
  /^Device:/ {devname=substr($0, 9)}
  /^Kernel:/ {
    split($2, a, "/");
    printf "  %s: %s\n", a[length(a)], devname
}' | sort -V

## Determine main display card
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
    if [ -z "$selected_card" ]  && [ "$status" = "connected" ]; then
        selected_card="$card"
        printf "  *"
    else
        printf "   "
    fi
    printf "%-25s%-20s%s\n" "$card_port" "$driver" "$status"
done
if [ -z "$selected_card" ]; then
    bashio::log.error "ERROR: No connected video card detected. Exiting.."
    exit 1
fi

#### Start Xorg
rm -rf /tmp/.X*-lock /tmp/.X11-unix 2>/dev/null || true
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

if [[ -n "$XORG_CONF" && "${XORG_APPEND_REPLACE}" = "replace" ]]; then
    bashio::log.info "Replacing default 'xorg.conf'..."
    echo "${XORG_CONF}" >| /etc/X11/xorg.conf
else
    cp -a /etc/X11/xorg.conf{.default,}
    sed -i "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\    Option     \t\t\"kmsdev\" \"/dev/dri/$selected_card\"" /etc/X11/xorg.conf
    if [ -z "$XORG_CONF" ]; then
        bashio::log.info "No user 'xorg.conf' data provided, using default..."
    elif [ "${XORG_APPEND_REPLACE}" = "append" ]; then
        bashio::log.info "Appending onto default 'xorg.conf'..."
        echo -e "\n#\n${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
fi

echo "."
printf '%*s xorg.conf %*s\n' 35 '' 34 '' | tr ' ' '#'
cat /etc/X11/xorg.conf
printf '%*s\n' 80 '' | tr ' ' '#'
echo "."

bashio::log.info "Starting X on DISPLAY=$DISPLAY..."
NOCURSOR=""
[ "$CURSOR_TIMEOUT" -lt 0 ] && NOCURSOR="-nocursor"

# CORRECTION CRITIQUE : Capturer le PID de Xorg
Xorg $NOCURSOR -novtswitch -nolisten tcp </dev/null &
XORG_PID=$!

XSTARTUP=30
bashio::log.info "Waiting for X server to start (PID: $XORG_PID)..."
for ((i=0; i<=XSTARTUP; i++)); do
    # Vérifier d'abord que le processus X tourne toujours
    if ! kill -0 "$XORG_PID" 2>/dev/null; then
        bashio::log.error "X server process died unexpectedly!"
        exit 1
    fi
    
    # Vérifier si X répond
    if DISPLAY=:0 xset q >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! xset q >/dev/null 2>&1; then
    bashio::log.error "Error: X server failed to start within $XSTARTUP seconds."
    exit 1
fi
bashio::log.info "X server started successfully after $i seconds..."

echo "xinput list:"
xinput list | sed 's/^/  /'

echo -e "\033[?25l" > /dev/console 2>/dev/null || true

if [ "$CURSOR_TIMEOUT" -gt 0 ]; then
    unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout "$CURSOR_TIMEOUT" 2>/dev/null || \
    unclutter --start-hidden --fork --timeout "$CURSOR_TIMEOUT" 2>/dev/null || true
fi

#### Start Window manager
WINMGR=Openbox
openbox &
O_PID=$!
sleep 0.5
if ! kill -0 "$O_PID" 2>/dev/null; then
    bashio::log.error "Failed to start $WINMGR window manager"
    exit 1
fi
bashio::log.info "$WINMGR window manager started successfully..."

#### Configure screen timeout
xset +dpms
xset s "$SCREEN_TIMEOUT"
xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
if [ "$SCREEN_TIMEOUT" -eq 0 ]; then
    bashio::log.info "Screen timeout disabled..."
else
    bashio::log.info "Screen timeout after $SCREEN_TIMEOUT seconds..."
fi

#### Configure outputs
readarray -t ALL_OUTPUTS < <(xrandr --query | awk '/^[[:space:]]*[A-Za-z0-9-]+/ {print $1}')
bashio::log.info "All video outputs: ${ALL_OUTPUTS[*]}"

readarray -t OUTPUTS < <(xrandr --query | awk '/ connected/ {print $1}')
if [ ${#OUTPUTS[@]} -eq 0 ]; then
    bashio::log.error "ERROR: No connected outputs detected. Exiting.."
    exit 1
fi

if [ "$OUTPUT_NUMBER" -gt "${#OUTPUTS[@]}" ]; then
    OUTPUT_NUMBER=${#OUTPUTS[@]}
fi
bashio::log.info "Connected video outputs: (Selected output marked with '*')"
for i in "${!OUTPUTS[@]}"; do
    marker=" "
    [ "$i" -eq "$((OUTPUT_NUMBER - 1))" ] && marker="*"
    bashio::log.info "  ${marker}[$((i + 1))] ${OUTPUTS[$i]}"
done
OUTPUT_NAME="${OUTPUTS[$((OUTPUT_NUMBER - 1))]}"

for OUTPUT in "${OUTPUTS[@]}"; do
    if [ "$OUTPUT" = "$OUTPUT_NAME" ]; then
        if [ "$ROTATE_DISPLAY" = normal ]; then
            xrandr --output "$OUTPUT_NAME" --primary --auto
        else
            xrandr --output "$OUTPUT_NAME" --primary --rotate "${ROTATE_DISPLAY}"
            bashio::log.info "Rotating $OUTPUT_NAME: ${ROTATE_DISPLAY}"
        fi
    else
        xrandr --output "$OUTPUT" --off
    fi
done

if [ "$MAP_TOUCH_INPUTS" = true ]; then
    while IFS= read -r id; do
        name=$(xinput list --name-only "$id" 2>/dev/null)
        [[ "${name,,}" =~ (^|[^[:alnum:]_])(touch|touchscreen|stylus)([^[:alnum:]_]|$) ]] || continue
        xinput_line=$(xinput list "$id" 2>/dev/null)
        [[ "$xinput_line" =~ \[(slave|master)[[:space:]]+keyboard[[:space:]]+\([0-9]+\)\] ]] && continue
        props="$(xinput list-props "$id" 2>/dev/null)"
        [[ "$props" = *"Coordinate Transformation Matrix"* ]] ||  continue
        xinput map-to-output "$id" "$OUTPUT_NAME" && RESULT="SUCCESS" || RESULT="FAILED"
        bashio::log.info "Mapping: input device [$id|$name] -->  $OUTPUT_NAME [$RESULT]"
    done < <(xinput list --id-only | sort -n)
fi

#### Set keyboard layout
setxkbmap "$KEYBOARD_LAYOUT"
export LANG=$KEYBOARD_LAYOUT
bashio::log.info "Setting keyboard layout and language to: $KEYBOARD_LAYOUT"
setxkbmap -query  | sed 's/^/  /'

### Get screen dimensions
read -r SCREEN_WIDTH SCREEN_HEIGHT < <(
    xrandr --query --current | grep "^$OUTPUT_NAME " |
    sed -n "s/^$OUTPUT_NAME connected.* \([0-9]\+\)x\([0-9]\+\)+.*$/\1 \2/p"
)

if [[ -n "$SCREEN_WIDTH" && -n "$SCREEN_HEIGHT" ]]; then
    bashio::log.info "Screen: Width=$SCREEN_WIDTH  Height=$SCREEN_HEIGHT"
else
    bashio::log.error "Could not determine screen size for output $OUTPUT_NAME"
fi

#### Onboard keyboard
if [[ "$ONSCREEN_KEYBOARD" = true && -n "$SCREEN_WIDTH" && -n "$SCREEN_HEIGHT" ]]; then
    if (( SCREEN_WIDTH >= SCREEN_HEIGHT )); then
        MAX_DIM=$SCREEN_WIDTH
        MIN_DIM=$SCREEN_HEIGHT
        ORIENTATION="landscape"
    else
        MAX_DIM=$SCREEN_HEIGHT
        MIN_DIM=$SCREEN_WIDTH
        ORIENTATION="portrait"
    fi

    KBD_ASPECT_RATIO_X10=30
    LAND_HEIGHT=$(( MIN_DIM / 3 ))
    LAND_WIDTH=$(( (LAND_HEIGHT * KBD_ASPECT_RATIO_X10) / 10 ))
    [ $LAND_WIDTH -gt "$MAX_DIM" ] && LAND_WIDTH=$MAX_DIM
    LAND_Y_OFFSET=$(( MIN_DIM - LAND_HEIGHT ))
    LAND_X_OFFSET=$(( (MAX_DIM - LAND_WIDTH) / 2 ))

    PORT_HEIGHT=$(( MAX_DIM / 4 ))
    PORT_WIDTH=$(( (PORT_HEIGHT * KBD_ASPECT_RATIO_X10) / 10 ))
    [ $PORT_WIDTH -gt "$MIN_DIM" ] && PORT_WIDTH=$MIN_DIM
    PORT_Y_OFFSET=$(( MAX_DIM - PORT_HEIGHT ))
    PORT_X_OFFSET=$(( (MIN_DIM - PORT_WIDTH) / 2 ))

    dconf write /org/onboard/layout "'/usr/share/onboard/layouts/Small.onboard'"
    dconf write /org/onboard/theme "'/usr/share/onboard/themes/Blackboard.theme'"
    dconf write /org/onboard/theme-settings/color-scheme "'/usr/share/onboard/themes/Charcoal.colors'"
    dconf write /org/onboard/auto-show/enabled true
    dconf write /org/onboard/auto-show/tablet-mode-detection-enabled false
    dconf write /org/onboard/window/force-to-top true
    gsettings set org.gnome.desktop.interface toolkit-accessibility true

    dconf write /org/onboard/window/landscape/height "$LAND_HEIGHT"
    dconf write /org/onboard/window/landscape/width "$LAND_WIDTH"
    dconf write /org/onboard/window/landscape/x "$LAND_X_OFFSET"
    dconf write /org/onboard/window/landscape/y "$LAND_Y_OFFSET"
    dconf write /org/onboard/window/portrait/height "$PORT_HEIGHT"
    dconf write /org/onboard/window/portrait/width "$PORT_WIDTH"
    dconf write /org/onboard/window/portrait/x "$PORT_X_OFFSET"
    dconf write /org/onboard/window/portrait/y "$PORT_Y_OFFSET"

    if [ -f "$ONBOARD_CONFIG_FILE" ]; then
        if [ "$SAVE_ONSCREEN_CONFIG" = true ]; then
            bashio::log.info "Restoring Onboard configuration from '$ONBOARD_CONFIG_FILE'"
            dconf load /org/onboard/ < "$ONBOARD_CONFIG_FILE"
        else
            rm -f "$ONBOARD_CONFIG_FILE"
        fi
    fi

    bashio::log.info "Starting Onboard onscreen keyboard"
    onboard &
    python3 /toggle_keyboard.py "$DARK_MODE" &
fi

#### Start REST server
bashio::log.info "Starting HAOSKiosk REST server..."
python3 /rest_server.py &
REST_PID=$!
bashio::log.info "REST server started with PID: $REST_PID"

################################################################################
#### FIREFOX LAUNCH
################################################################################
if [ "$DEBUG_MODE" != true ]; then
    # Créer un profil Firefox temporaire
    FIREFOX_PROFILE="/tmp/firefox-kiosk-profile"
    rm -rf "$FIREFOX_PROFILE" 2>/dev/null
    mkdir -p "$FIREFOX_PROFILE"
    
    bashio::log.info "Creating Firefox profile at: $FIREFOX_PROFILE"
    
    # Configurer Firefox pour le kiosk
    cat > "$FIREFOX_PROFILE/user.js" << EOF
// Configuration Firefox Kiosk
user_pref("browser.startup.homepage", "${HA_URL}/${HA_DASHBOARD}");
user_pref("browser.fullscreen.autohide", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("devtools.debugger.remote-enabled", true);
user_pref("devtools.chrome.enabled", true);
user_pref("devtools.debugger.prompt-connection", false);
user_pref("privacy.donottrackheader.enabled", true);
user_pref("geo.enabled", false);
user_pref("general.warnOnAboutConfig", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.link.open_newwindow", 1);
user_pref("browser.link.open_newwindow.restriction", 0);
EOF

    bashio::log.info "Firefox profile configuration created"
    
    # Vérifier que Firefox est disponible
    if ! command -v firefox >/dev/null 2>&1; then
        bashio::log.error "ERROR: Firefox command not found!"
        exit 1
    fi
    
    bashio::log.info "Firefox binary found at: $(which firefox)"
    
    # Attendre que X soit vraiment prêt
    bashio::log.info "Waiting for X server to be fully ready..."
    sleep 2
    
    # URL complète
    FULL_URL="${HA_URL}/${HA_DASHBOARD}"
    bashio::log.info "Launching Firefox in kiosk mode..."
    bashio::log.info "Target URL: $FULL_URL"
    
    # Créer un fichier de log pour Firefox
    FIREFOX_LOG="/tmp/firefox-kiosk.log"
    
    # Lancer Firefox avec logs détaillés
    DISPLAY=:0 firefox \
        --kiosk \
        --new-instance \
        --profile "$FIREFOX_PROFILE" \
        "$FULL_URL" \
        > "$FIREFOX_LOG" 2>&1 &
    
    FIREFOX_PID=$!
    bashio::log.info "Firefox launched with PID: $FIREFOX_PID"
    
    # Attendre un peu et vérifier que Firefox tourne
    sleep 3
    
    if ! kill -0 "$FIREFOX_PID" 2>/dev/null; then
        bashio::log.error "ERROR: Firefox process died immediately!"
        bashio::log.error "Firefox log output:"
        cat "$FIREFOX_LOG" 2>/dev/null | sed 's/^/  /' || echo "  (no log file)"
        exit 1
    fi
    
    bashio::log.info "Firefox is running (PID: $FIREFOX_PID)"
    
    # Vérifier que la fenêtre est apparue
    bashio::log.info "Checking for Firefox window..."
    WAIT_WINDOW=10
    WINDOW_FOUND=false
    
    for ((i=0; i<WAIT_WINDOW; i++)); do
        if xdotool search --name "Firefox" >/dev/null 2>&1; then
            WINDOW_FOUND=true
            WINDOW_COUNT=$(xdotool search --name "Firefox" 2>/dev/null | wc -l)
            bashio::log.info "✓ Firefox window detected! ($WINDOW_COUNT window(s))"
            break
        fi
        sleep 1
    done
    
    if [ "$WINDOW_FOUND" = false ]; then
        bashio::log.warning "WARNING: Firefox window not detected after ${WAIT_WINDOW}s"
        bashio::log.warning "But process is still running, continuing..."
    fi
    
    # Auto-login avec xdotool
    bashio::log.info "Waiting ${LOGIN_DELAY}s before attempting auto-login..."
    sleep "$LOGIN_DELAY"
    
    # Script d'auto-login
    (
        sleep 2
        bashio::log.info "Attempting Firefox auto-login..."
        
        # Chercher la fenêtre Firefox
        WINDOW_ID=$(xdotool search --name "Firefox" 2>/dev/null | head -1)
        
        if [ -n "$WINDOW_ID" ]; then
            bashio::log.info "Found Firefox window: $WINDOW_ID"
            
            # Activer la fenêtre
            xdotool windowactivate --sync "$WINDOW_ID"
            sleep 1
            
            # S'assurer que la fenêtre est en focus
            xdotool windowfocus "$WINDOW_ID"
            sleep 0.5
            
            bashio::log.info "Typing username..."
            xdotool type --delay 100 "$HA_USERNAME"
            xdotool key Tab
            sleep 0.5
            
            bashio::log.info "Typing password..."
            xdotool type --delay 100 "$HA_PASSWORD"
            sleep 0.5
            
            bashio::log.info "Submitting login form..."
            xdotool key Return
            
            sleep 2
            bashio::log.info "✓ Auto-login sequence completed"
        else
            bashio::log.warning "Could not find Firefox window for auto-login"
        fi
    ) &
    
    # Monitoring du processus Firefox
    bashio::log.info "Monitoring Firefox process..."
    while kill -0 "$FIREFOX_PID" 2>/dev/null; do
        sleep 30
    done
    
    bashio::log.error "Firefox process terminated unexpectedly!"
    exit 1
    
else
    ### Debug mode
    bashio::log.info "==================================="
    bashio::log.info "DEBUG MODE ACTIVATED"
    bashio::log.info "==================================="
    exec sleep infinite
fi
