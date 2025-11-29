#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Lutumba Kiosk Add-on
# ==============================================================================

# ------------------------------------------------------------------------------
# SETUP ET VARIABLES
# ------------------------------------------------------------------------------

bashio::log.info "Starting HAOS Lutumba Kiosk..."

# Variables de configuration
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
REST_AUTH_TOKEN=$(bashio::config 'rest_authorization_token')
ALLOW_USER_COMMANDS=$(bashio::config 'allow_user_commands')
DEBUG_MODE=$(bashio::config 'debug_mode')

# Construction de l'URL finale
if [ -z "${HA_DASHBOARD}" ]; then
    URL="${HA_URL}"
else
    URL="${HA_URL}${HA_DASHBOARD}"
fi

# Création du profil Firefox persistant
mkdir -p /config/firefox_profile
bashio::log.info "Firefox profile set to /config/firefox_profile for persistence."

# ------------------------------------------------------------------------------
# GESTION DES FICHIERS DE CONFIGURATION
# ------------------------------------------------------------------------------

# Appliquer la configuration Xorg personnalisée si fournie
if [ ! -z "${XORG_CONF}" ]; then
    if [ "${XORG_APPEND_REPLACE}" == "replace" ]; then
        bashio::log.info "Replacing /etc/X11/xorg.conf with custom code."
        echo "${XORG_CONF}" > /etc/X11/xorg.conf
    else
        bashio::log.info "Appending custom code to /etc/X11/xorg.conf."
        echo "${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
else
    bashio::log.info "Using default xorg.conf configuration."
    cp /etc/X11/xorg.conf.default /etc/X11/xorg.conf
fi


# Configuration de l'affichage (Output Number)
if [ "${OUTPUT_NUMBER}" -gt 1 ]; then
    bashio::log.info "Setting primary output to ${OUTPUT_NUMBER}."
    echo -e '\nSection "Screen"\n\tIdentifier "Screen0"\n\tMonitor "Monitor0"\n\tDevice "Card0"\n\tDefaultDepth 24\n\tSubSection "Display"\n\t\tViewport 0 0\n\t\tDepth 24\n\t\tVirtual 1920 1080\n\tEndSubSection\nEndSection' >> /etc/X11/xorg.conf
    # Note: L'utilisateur devra ajuster si l'output > 1 n'est pas géré par xorg-server par défaut.
fi


# ------------------------------------------------------------------------------
# GESTION DU MODE DEBUG
# ------------------------------------------------------------------------------

# Démarrer le serveur X
bashio::log.info "Starting X server..."
Xorg :0 -config /etc/X11/xorg.conf &

# Attendre que le serveur X démarre
sleep 2

# Mode Debug: Ne pas lancer le navigateur
if bashio::var.true "${DEBUG_MODE}"; then
    bashio::log.warning "Debug mode enabled. Browser will not be launched. Use SSH
