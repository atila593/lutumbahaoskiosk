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
REST_AUTHORIZATION_TOKEN=$(bashio::config 'rest_authorization_token')
ALLOW_USER_COMMANDS=$(bashio::config 'allow_user_commands')
DEBUG_MODE=$(bashio::config 'debug_mode')

# Définition de l'URL cible
if [ -n "${HA_DASHBOARD}" ]; then
    TARGET_URL="${HA_URL}/lovelace/${HA_DASHBOARD}"
else
    TARGET_URL="${HA_URL}"
fi

# Définition du répertoire de profil Firefox
PROFILE_DIR="/config/firefox_profile"
mkdir -p "${PROFILE_DIR}"

# ------------------------------------------------------------------------------
# 2. XORG CONFIGURATION & DISPLAY STARTUP (Fix du PID 1/s6-overlay)
# ------------------------------------------------------------------------------

XORG_CONFIG_FILE="/etc/X11/xorg.conf"
DEFAULT_CONFIG_FILE="/xorg.conf.default" # Le fichier fourni dans l'addon
CUSTOM_XORG_CONF=$(bashio::config 'xorg_conf')

# 2.1 Préparation du fichier xorg.conf
if [ ! -f "${DEFAULT_CONFIG_FILE}" ]; then
    bashio::log.error "Le fichier de configuration par défaut Xorg (${DEFAULT_CONFIG_FILE}) est manquant."
    # Si le fichier par défaut est manquant, on crée un fichier minimal (solution de dernier recours)
    echo "Section \"ServerLayout\"" > "${XORG_CONFIG_FILE}"
    echo "    Identifier \"DefaultLayout\"" >> "${XORG_CONFIG_FILE}"
    echo "    Screen 0 \"Screen0\" 0 0" >> "${XORG_CONFIG_FILE}"
    echo "EndSection" >> "${XORG_CONFIG_FILE}"
    bashio::log.info "Création d'un fichier xorg.conf minimal en dernier recours."
else
    # 2.2 Application de la configuration personnalisée
    if bashio::config.is_set 'xorg_conf'; then
        if [ "${XORG_APPEND_REPLACE}" == "replace" ]; then
            # Remplacer entièrement le fichier
            bashio::log.info "Remplacement de la configuration Xorg ('replace')."
            echo "${CUSTOM_XORG_CONF}" > "${XORG_CONFIG_FILE}"
        else
            # Utiliser 'append' (par défaut ou si mode inconnu)
            bashio::log.info "Création de xorg.conf à partir du défaut, puis ajout ('append')."
            cp "${DEFAULT_CONFIG_FILE}" "${XORG_CONFIG_FILE}"
            echo -e "\n# --- Custom Configuration ---\n${CUSTOM_XORG_CONF}\n# ----------------------------" >> "${XORG_CONFIG_FILE}"
        fi
    else
        # Utiliser la configuration par défaut sans personnalisation
        cp "${DEFAULT_CONFIG_FILE}" "${XORG_CONFIG_FILE}"
        bashio::log.info "Utilisation de la configuration Xorg par défaut (pas de personnalisation)."
    fi
fi


# 2.3 Lancement de Xorg (Méthode simple pour s6-overlay)
bashio::log.info "Démarrage du serveur Xorg..."

# Nettoyage des verrous X11 précédents (anti-crash)
rm -f /tmp/.X0-lock

# Lancement direct de l'exécutable Xorg en arrière-plan
Xorg :0 -config "${XORG_CONFIG_FILE}" -nolisten tcp -vt"${OUTPUT_NUMBER}" &
XORG_PID=$!

# Attendre que le serveur X soit opérationnel
# On teste l'existence du fichier de socket de l'écran 0.
X_SOCKET_PATH="/tmp/.X11-unix/X0"
X_WAIT_TIMEOUT=15
X_WAIT_COUNT=0
bashio::log.info "Attente du démarrage du serveur Xorg (max ${X_WAIT_TIMEOUT}s)..."
while [ ! -e "${X_SOCKET_PATH}" ] && [ $X_WAIT_COUNT -lt $X_WAIT_TIMEOUT ]; do
    sleep 1
    X_WAIT_COUNT=$((X_WAIT_COUNT + 1))
done

if [ ! -e "${X_SOCKET_PATH}" ]; then
    bashio::log.error "Le serveur Xorg n'a pas démarré après ${X_WAIT_COUNT} secondes. Arrêt de l'addon."
    # On force la sortie pour que l'addon se redémarre (si configuré)
    exit 1
fi

bashio::log.info "Serveur Xorg démarré avec succès."

# Export DISPLAY pour toutes les applications graphiques suivantes (Openbox, Firefox, xrandr, setxkbmap...)
export DISPLAY=:0


# ------------------------------------------------------------------------------
# 3. GESTIONNAIRE DE FENÊTRES & UTILITAIRES GRAPHIQUES (Déplacé après le démarrage de Xorg)
# ------------------------------------------------------------------------------

# Lancement du gestionnaire de fenêtres Openbox
bashio::log.info "Démarrage du gestionnaire de fenêtres Openbox..."
openbox &
OPENBOX_PID=$!

# Donner un petit moment à Openbox pour s'initialiser et permettre aux outils graphiques de fonctionner
sleep 1

# 3.1 Configuration de la rotation de l'écran (maintenant que Xorg est prêt)
if [ "${ROTATE_DISPLAY}" != "normal" ]; then
    bashio::log.info "Application de la rotation d'écran : ${ROTATE_DISPLAY}"
    # On itère sur tous les écrans connectés pour appliquer la rotation.
    XRANDR_OUTPUT=$(xrandr -q | grep ' connected' | awk '{print $1}')
    if [ -z "${XRANDR_OUTPUT}" ]; then
        bashio::log.warning "Aucun écran connecté trouvé par xrandr. Impossible d'appliquer la rotation."
    else
        for OUTPUT in ${XRANDR_OUTPUT}; do
            bashio::log.info "Rotation de l'écran ${OUTPUT} vers ${ROTATE_DISPLAY}."
            # L'opérateur '|| bashio::log.warning' est utilisé pour capturer les erreurs sans stopper le script
            xrandr --output "${OUTPUT}" --rotate "${ROTATE_DISPLAY}" || bashio::log.warning "Échec de l'application de xrandr pour ${OUTPUT}."
        done
    fi
else
    bashio::log.info "Aucune rotation d'écran spécifiée ('normal')."
fi

# 3.2 Configuration du clavier (maintenant que Xorg est prêt)
if [ -n "${KEYBOARD_LAYOUT}" ]; then
    bashio::log.info "Configuration du clavier : setxkbmap ${KEYBOARD_LAYOUT}"
    setxkbmap "${KEYBOARD_LAYOUT}" || bashio::log.warning "Échec de l'application de setxkbmap pour la disposition ${KEYBOARD_LAYOUT}."
else
    bashio::log.info "Aucune configuration de clavier spécifiée."
fi

# 3.3 Gestion de l'extinction d'écran via xset
if [ "${SCREEN_TIMEOUT}" != "0" ]; then
    bashio::log.info "Configuration de l'extinction d'écran après ${SCREEN_TIMEOUT} secondes."
    xset s "${SCREEN_TIMEOUT}" || true
    xset dpms 0 0 0 || true
    xset s activate || true
else
    bashio::log.info "Désactivation de l'extinction d'écran."
    xset s off || true
    xset -dpms || true
fi

# 3.4 Lancement de l'utilitaire unclutter (pour cacher le curseur)
if bashio::config.is_not_set 'cursor_timeout' || [ "$(bashio::config 'cursor_timeout')" -gt 0 ]; then
    TIMEOUT_SECONDS=$(bashio::config 'cursor_timeout')
    bashio::log.info "Démarrage d'unclutter (cache le curseur après ${TIMEOUT_SECONDS}s)."
    # Utiliser unclutter-xfixes si disponible, sinon la version simple
    if command -v unclutter-xfixes &> /dev/null; then
        unclutter-xfixes -idle "${TIMEOUT_SECONDS}" -root &
    else
        unclutter -idle "${TIMEOUT_SECONDS}" -root -noevents &
    fi
    UNCLUTTER_PID=$!
fi

# 3.5 Lancement du clavier virtuel 'onboard'
if bashio::config.true 'onscreen_keyboard'; then
    bashio::log.info "Démarrage du clavier virtuel Onboard..."
    # Onboard est lancé en arrière-plan
    onboard -l "${KEYBOARD_LAYOUT}" &
    ONBOARD_PID=$!
    
    # Lancement du petit bouton pour basculer le clavier
    bashio::log.info "Démarrage du bouton de bascule du clavier (toggle_keyboard.py)..."
    python3 /toggle_keyboard.py &
    TOGGLE_PID=$!
fi

# 3.6 Démarrage du serveur REST
bashio::log.info "Démarrage du serveur REST CherryPy..."
# Le serveur REST est lancé en arrière-plan
# Le processus doit être lancé en arrière-plan et géré par la boucle principale
python3 /rest_server.py &
REST_SERVER_PID=$!

# ------------------------------------------------------------------------------
# 4. PRÉPARATION ET LANCEMENT DE FIREFOX
# ------------------------------------------------------------------------------

# 4.1. Application des paramètres Firefox (dark mode, zoom, refresh)
bashio::log.info "Application des paramètres Firefox : zoom=${ZOOM_LEVEL}%, refresh=${BROWSER_REFRESH}s, dark_mode=${DARK_MODE}."

# Créer un fichier de préférences minimal (prefs.js)
PREFS_FILE="${PROFILE_DIR}/prefs.js"
echo "user_pref(\"toolkit.defaultChromeURI\", \"chrome://browser/content/browser.xhtml\");" > "${PREFS_FILE}"
echo "user_pref(\"browser.sessionstore.resume_from_crash\", false);" >> "${PREFS_FILE}"
echo "user_pref(\"layout.css.prefers-color-scheme.content-override\", $(if bashio::var.true "${DARK_MODE}"; then echo 2; else echo 1; fi));" >> "${PREFS_FILE}" # 1:light, 2:dark

# Injecter le niveau de zoom dans l'UI et le contenu
echo "user_pref(\"browser.display.background_content.last_zoom_setting\", ${ZOOM_LEVEL});" >> "${PREFS_FILE}"
echo "user_pref(\"browser.content.full-zoom\", true);" >> "${PREFS_FILE}"
# Utiliser bc pour un calcul plus précis et sûr
echo "user_pref(\"layout.css.devPixelsPerPx\", \"$(echo "scale=2; ${ZOOM_LEVEL} / 100" | bc)\");" >> "${PREFS_FILE}"

# Désactiver la mise en cache (optionnel, mais utile en mode Kiosk)
echo "user_pref(\"browser.cache.disk.enable\", false);" >> "${PREFS_FILE}"
echo "user_pref(\"browser.cache.memory.enable\", false);" >> "${PREFS_FILE}"
echo "user_pref(\"browser.tabs.remote.autostart\", false);" >> "${PREFS_FILE}"
echo "user_pref(\"browser.tabs.remote.autostart.2\", false);" >> "${PREFS_FILE}"
echo "user_pref(\"browser.tabs.closeWindowWithLastTab\", false);" >> "${PREFS_FILE}"
echo "user_pref(\"general.useragent.override\", \"haos_kiosk\");" >> "${PREFS_FILE}" # Pour browser_mod

# 4.2. Génération du script d'injection JS
# Le script est injecté une fois après le lancement initial de Firefox.
JS_CODE="
// Script d'injection dans la page pour les commandes post-chargement
(function() {
    const DEBUG_MODE = $(if bashio::var.true "${DEBUG_MODE}"; then echo 'true'; else echo 'false'; fi);
    const BROWSER_REFRESH = parseInt(\"${BROWSER_REFRESH}\");
    const HA_SIDEBAR = $(if bashio::var.true "${HA_SIDEBAR}"; then echo 'true'; else echo 'false'; fi);
    const SCREEN_TIMEOUT = parseInt(\"${SCREEN_TIMEOUT}\");

    if (DEBUG_MODE) console.log('Kiosk Script: Démarrage de l\'injection JS.');

    // 1. Gestion du rafraîchissement périodique
    if (BROWSER_REFRESH > 0) {
        if (DEBUG_MODE) console.log('Kiosk Script: Configuration du rafraîchissement toutes les ' + BROWSER_REFRESH + ' secondes.');
        if (!window.kioskRefreshInterval) {
            window.kioskRefreshInterval = setInterval(function() {
                window.location.reload(true);
            }, BROWSER_REFRESH * 1000);
        }
    }

    // 2. Gestion de la sidebar (masquage)
    if (HA_SIDEBAR === false) {
        if (DEBUG_MODE) console.log('Kiosk Script: Tentative de masquer la sidebar Home Assistant.');
        
        // Fonction pour cacher la sidebar en cliquant sur le bouton menu
        const attemptHide = () => {
            try {
                // Recherche du bouton menu dans le shadow DOM de HA
                const main = document.querySelector('home-assistant');
                if (main && main.shadowRoot) {
                    const haMain = main.shadowRoot.querySelector('home-assistant-main');
                    if (haMain && haMain.shadowRoot) {
                        const toolbar = haMain.shadowRoot.querySelector('app-header').querySelector('app-toolbar');
                        if (toolbar) {
                            // Clic sur l'icône du menu (le premier ha-icon-button dans la barre)
                            const menuButton = toolbar.querySelector('ha-icon-button');
                            if (menuButton && menuButton.getAttribute('icon') === 'mdi:menu') {
                                menuButton.click();
                                if (DEBUG_MODE) console.log('Kiosk Script: Sidebar masquée via clic sur le menu.');
                                return true;
                            }
                        }
                    }
                }
            } catch (e) {
                if (DEBUG_MODE) console.error('Kiosk Script: Erreur lors du masquage de la sidebar:', e);
            }
            return false;
        };

        // Essayer de masquer immédiatement, puis réessayer après un court délai au cas où le chargement est lent
        if (!attemptHide()) {
             setTimeout(attemptHide, 2000);
             setTimeout(attemptHide, 5000); // Seconde tentative
        }
    }

    // 3. Gestion du timeout de l'écran (si > 0)
    if (SCREEN_TIMEOUT > 0) {
        if (DEBUG_MODE) console.log('Kiosk Script: Configuration du timeout d\'écran après ' + SCREEN_TIMEOUT + ' secondes d\'inactivité.');
        let timeoutHandle;
        const REST_PORT = \"${REST_PORT}\";
        const AUTH_TOKEN = \"${REST_AUTHORIZATION_TOKEN}\";

        function sendCommand(command) {
            fetch(\`http://127.0.0.1:\${REST_PORT}/url_command\`, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    command: command,
                    authorization_token: AUTH_TOKEN
                })
            }).catch(e => {
                if (DEBUG_MODE) console.error(\`Kiosk Script: Erreur lors de la commande \${command}:\`, e);
            });
        }
        
        function turnScreenOff() {
            if (DEBUG_MODE) console.log('Kiosk Script: Inactivité détectée. Extinction de l\'écran (via API REST).');
            sendCommand('screen_off');
        }
        
        function resetTimer() {
            clearTimeout(timeoutHandle);
            timeoutHandle = setTimeout(turnScreenOff, SCREEN_TIMEOUT * 1000);
            
            // Si l'écran était éteint, cette activité le rallumera
            sendCommand('screen_on');
        }

        ['mousemove', 'mousedown', 'keydown', 'touchstart'].forEach(event => {
            document.addEventListener(event, resetTimer, { passive: true });
        });
        
        // Démarrer le timer initial
        resetTimer();
    }
    
})();
"

# Rendre le script accessible pour l'injection via xdotool
JS_INJECTION_FILE="/home_assistant_kiosk.js"
echo "${JS_CODE}" > "${JS_INJECTION_FILE}"

# Copier le JS dans le presse-papiers pour l'injection par xdotool
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
    bashio::log.info "Tentative d'injection du script JS (Sidebar/Refresh/Timeout)."
    # On envoie Ctrl+Shift+K (console), on tape ce qui est dans le presse-papiers, Entrée, Échap (fermeture)
    # On utilise search + windowfocus pour s'assurer que l'injection cible Firefox, même si la fenêtre n'a pas encore le focus
    # On ajoute un délai après la recherche pour que la fenêtre soit vraiment prête à recevoir les frappes
    xdotool search --name "Mozilla Firefox" --onlyvisible --pid "${FIREFOX_PID}" windowfocus key --delay 200 "control+shift+k" type --delay 100 --clearmodifiers "$(xclip -o -selection clipboard)" key "Return" key "Escape" 2>/dev/null || bashio::log.warning "Échec de l'injection JavaScript via xdotool. Le script d'auto-login/refresh peut ne pas s'être exécuté."


    # Attendre que Firefox se termine.
    wait $FIREFOX_PID
    
    # Si on arrive ici, Firefox a crashé ou a été fermé
    bashio::log.warning "Firefox s'est arrêté (PID: ${FIREFOX_PID}). Redémarrage dans 5 secondes..."
    sleep 5
done

# ------------------------------------------------------------------------------
# 5. NETTOYAGE (normalement jamais atteint)
# ------------------------------------------------------------------------------

# Arrêter les processus en arrière-plan si la boucle s'arrêtait
kill $XORG_PID $OPENBOX_PID $REST_SERVER_PID $ONBOARD_PID $TOGGLE_PID 2>/dev/null
bashio::log.info "Arrêt de l'addon."
exit 0
