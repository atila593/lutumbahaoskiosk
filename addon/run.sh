#!/usr/bin/with-contenv bashio
set -e

bashio::log.info "Démarrage du Kiosque Firefox HAOS..."

# ------------------------------------------------------------------------------
# 1. CONFIGURATION & VARIABLES
# ------------------------------------------------------------------------------

# Récupération de toutes les variables de configuration (identiques à l'original)
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

# Construction de l'URL cible
if [ -z "${HA_DASHBOARD}" ]; then
    TARGET_URL="${HA_URL}"
else
    # S'assurer que le chemin est correct, puis nettoyer les double slashs
    TARGET_URL="${HA_URL}/${HA_DASHBOARD}"
fi
TARGET_URL=$(echo "$TARGET_URL" | sed 's|[^:]//|/|g')

# Dossier de profil persistant de Firefox (pour sauvegarder le login)
PROFILE_DIR="/config/firefox_profile"
mkdir -p "$PROFILE_DIR"

# ------------------------------------------------------------------------------
# 2. CONFIGURATION XORG (AFFICHAGE ET ROTATION)
# ------------------------------------------------------------------------------

# Nettoyage des verrous X11 précédents (anti-crash)
rm -f /tmp/.X0-lock

# Gestion du xorg.conf personnalisé
bashio::log.info "Configuration de /etc/X11/xorg.conf..."
if [ ! -z "${XORG_CONF}" ]; then
    if [ "${XORG_APPEND_REPLACE}" == "replace" ]; then
        echo "${XORG_CONF}" > /etc/X11/xorg.conf
    else
        cp /etc/X11/xorg.conf.default /etc/X11/xorg.conf
        echo "${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
else
    cp /etc/X11/xorg.conf.default /etc/X11/xorg.conf
fi

# Démarrage Xorg en background
bashio::log.info "Démarrage du serveur Xorg..."
Xorg :0 -config /etc/X11/xorg.conf -nolisten tcp -vt1 &
export DISPLAY=:0

# Attente que Xorg soit prêt (timeout après 10s)
timeout 10 bash -c 'until xset q > /dev/null 2>&1; do sleep 0.5; done' || bashio::log.warning "Le serveur Xorg peut ne pas être prêt. Poursuite..."

# Rotation de l'écran via xrandr si nécessaire
if [ "${ROTATE_DISPLAY}" != "normal" ]; then
    bashio::log.info "Rotation de l'affichage vers ${ROTATE_DISPLAY}..."
    OUTPUT_NAME=$(xrandr | grep " connected" | cut -d ' ' -f1 | head -n 1)
    if [ ! -z "${OUTPUT_NAME}" ]; then
        xrandr --output "${OUTPUT_NAME}" --rotate "${ROTATE_DISPLAY}"
    else
        bashio::log.warning "Impossible de trouver l'affichage connecté pour la rotation."
    fi
fi

# Définir le layout clavier
if [ ! -z "${KEYBOARD_LAYOUT}" ]; then
    bashio::log.info "Définition du layout clavier à ${KEYBOARD_LAYOUT}."
    setxkbmap -layout "${KEYBOARD_LAYOUT}"
fi

# Gestion du Screen Timeout via xset
if [ "${SCREEN_TIMEOUT}" != "0" ]; then
    bashio::log.info "Configuration de l'extinction d'écran après ${SCREEN_TIMEOUT} secondes."
    xset s ${SCREEN_TIMEOUT}
    xset dpms 0 0 0
    xset s activate
else
    bashio::log.info "Désactivation de l'extinction d'écran."
    xset s off
    xset -dpms
fi

# Démarrage du gestionnaire de fenêtres
bashio::log.info "Démarrage du gestionnaire de fenêtres Openbox..."
openbox &

# ------------------------------------------------------------------------------
# 3. OUTILS ADDITIONNELS (Clavier, Curseur, Scripts Python)
# ------------------------------------------------------------------------------

# Masquer le curseur
if [ "${CURSOR_TIMEOUT}" != "-1" ]; then
    bashio::log.info "Démarrage d'Unclutter (Masque le curseur après ${CURSOR_TIMEOUT}s)..."
    unclutter -idle "${CURSOR_TIMEOUT}" -root &
fi

# Clavier virtuel
if bashio::var.true "${ONSCREEN_KEYBOARD}"; then
    bashio::log.info "Démarrage du clavier Onboard et du script de bascule (toggle)..."
    onboard &
    # Lancement du script Python pour le bouton de bascule du clavier
    python3 /toggle_keyboard.py &
fi

# Serveur REST (Démarré s'il est utilisé)
if [ -f /rest_server.py ]; then
    bashio::log.info "Démarrage du serveur REST API..."
    python3 /rest_server.py &
fi

# ------------------------------------------------------------------------------
# 4. PRÉPARATION DE FIREFOX (Configuration via user.js)
# ------------------------------------------------------------------------------

# Nettoyage des verrous Firefox (anti-crash)
rm -f "${PROFILE_DIR}/lock" "${PROFILE_DIR}/.parentlock"

bashio::log.info "Configuration des Préférences Firefox (user.js)..."

# Création du fichier user.js pour forcer les préférences (remplace userconf.lua)
cat > "${PROFILE_DIR}/user.js" <<EOF
// Gestion du Dark Mode (Adapté à Firefox)
user_pref("ui.systemUsesDarkTheme", $(if bashio::var.true "${DARK_MODE}"; then echo 1; else echo 0; fi));
user_pref("browser.theme.content-theme", $(if bashio::var.true "${DARK_MODE}"; then echo 0; else echo 2; fi));
user_pref("browser.theme.toolbar-theme", $(if bashio::var.true "${DARK_MODE}"; then echo 0; else echo 2; fi));

# Gestion du Zoom (on convertit ex: 120 -> 1.2)
user_pref("layout.css.devPixelsPerPx", "$(awk "BEGIN {print ${ZOOM_LEVEL}/100}")");

# Désactiver la restauration de session (anti-popup "Restaurer les onglets ?")
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);

# Désactiver les mises à jour et télémétrie
user_pref("app.update.auto", false);
user_pref("app.update.enabled", false);
user_pref("toolkit.telemetry.enabled", false);

# Autoriser l'autoplay (utile pour les caméras HA)
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.blocking_policy", 0);

# Set browser_mod-browser-id pour l'intégration Home Assistant (simule Luakit)
user_pref("general.useragent.override", "haos_kiosk");

# Désactiver l'interface utilisateur de premier lancement
user_pref("browser.aboutwelcome.enabled", false);
EOF

# ------------------------------------------------------------------------------
# 5. DÉMARRAGE DU NAVIGATEUR ET BOUCLE DE SURVEILLANCE
# ------------------------------------------------------------------------------

# Vérification du mode DEBUG : Si activé, on quitte sans lancer le navigateur
if bashio::var.true "${DEBUG_MODE}"; then
    bashio::log.warning "Mode Debug activé. Le navigateur n'est pas lancé. Le serveur Xorg tourne."
    # On reste en vie indéfiniment pour que l'utilisateur puisse se connecter via SSH.
    while true; do sleep 30; done
fi

# Script JavaScript pour injecter le Refresh et cacher la Sidebar
# L'injection se fera via xdotool (Ctrl+Shift+K)
JS_CODE="
(function() {
    // 1. Cacher la Sidebar de Home Assistant
    const ha_sidebar_hidden = $(if bashio::var.true "${HA_SIDEBAR}"; then echo "false"; else echo "true"; fi);
    try {
        const main = document.querySelector('home-assistant-main');
        if (main && ha_sidebar_hidden) {
            const sidebar = main.shadowRoot.querySelector('ha-sidebar');
            if (sidebar) {
                sidebar.style.display = 'none';
                console.log('HA Sidebar cachée par script.');
            }
        }
    } catch (e) { console.error('Erreur en cachant la sidebar:', e); }

    // 2. Gestion du Refresh Automatique
    const refresh_interval = parseInt(\"${BROWSER_REFRESH}\");
    if (refresh_interval > 0) {
        window.ha_refresh_id = setInterval(() => {
            console.log('Rafraîchissement automatique du navigateur...');
            window.location.reload();
        }, refresh_interval * 1000);
        console.log('Rafraîchissement automatique configuré pour ' + refresh_interval + ' secondes.');
    }
})();
"
# Le script JS est copié dans le presse-papiers pour l'injection via xdotool
# NOTE: L'add-on doit avoir 'xclip' installé dans le Dockerfile pour que cette commande fonctionne
echo "${JS_CODE}" | xclip -selection clipboard

bashio::log.info "Attente de ${LOGIN_DELAY} secondes avant le lancement de Firefox..."
sleep "${LOGIN_DELAY}"

bashio::log.info "Démarrage de Firefox à l'URL : ${TARGET_URL}"

# Boucle de surveillance : si Firefox crash, on le relance
while true; do
    # On lance Firefox en mode Kiosk
    firefox-esr \
        --kiosk \
        --no-remote \
        --profile "${PROFILE_DIR}" \
        "${TARGET_URL}" &
    
    FIREFOX_PID=$!
    
    # Attendre que la fenêtre Firefox soit visible
    sleep 5
    
    # Injection du script JS : Ouvre la console, colle le script, appuie sur Entrée, et ferme la console.
    bashio::log.info "Tentative d'injection du script JS (Sidebar/Refresh)."
    # On envoie Ctrl+Shift+K (console), on tape ce qui est dans le presse-papiers, Entrée, Échap (fermeture)
    xdotool search --pid "${FIREFOX_PID}" --onlyvisible --class "firefox" windowfocus key --delay 200 "control+shift+k" type --delay 100 --clearmodifiers "$(xclip -o -selection clipboard)" key "Return" key "Escape" 2>/dev/null

    # Attendre que Firefox se termine.
    wait $FIREFOX_PID
    
    # Si on arrive ici, Firefox a crashé ou a été fermé
    bashio::log.error "Firefox a quitté ou a crashé (Exit code $?). Redémarrage dans 5 secondes..."
    sleep 5
    # Nettoyage préventif avant relance (anti-lock)
    rm -f "${PROFILE_DIR}/lock" "${PROFILE_DIR}/.parentlock"
done
