#!/usr/bin/with-contenv bashio
set -e

bashio::log.info "Démarrage du Kiosque Firefox HAOS..."

# ------------------------------------------------------------------------------
# 1. CONFIGURATION & VARIABLES
# ------------------------------------------------------------------------------

# Récupération de toutes les variables de configuration
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
        # Rend la commande non fatale
        xrandr --output "${OUTPUT_NAME}" --rotate "${ROTATE_DISPLAY}" || true
    else
        bashio::log.warning "Impossible de trouver l'affichage connecté pour la rotation."
    fi
fi

# Définir le layout clavier
if [ ! -z "${KEYBOARD_LAYOUT}" ]; then
    bashio::log.info "Définition du layout clavier à ${KEYBOARD_LAYOUT}."
    # Rend la commande non fatale
    setxkbmap -layout "${KEYBOARD_LAYOUT}" || true
fi

# Gestion du Screen Timeout via xset
if [ "${SCREEN_TIMEOUT}" != "0" ]; then
    bashio::log.info "Configuration de l'extinction d'écran après ${SCREEN_TIMEOUT} secondes."
    # Rend les commandes non fatales
    xset s ${SCREEN_TIMEOUT} || true
    xset dpms 0 0 0 || true
    xset s activate || true
else
    bashio::log.info "Désactivation de l'extinction d'écran."
    # Rend les commandes non fatales
    xset s off || true
    xset -dpms || true
fi

# Démarrage du gestionnaire de fenêtres
bashio::log.info "Démarrage du gestionnaire de fenêtres Openbox..."
openbox &

# ------------------------------------------------------------------------------
# 3. OUTILS ADDITIONNELS (Clavier, Curseur, Serveur REST)
# ------------------------------------------------------------------------------

# Masquer le curseur
if [ "${CURSOR_TIMEOUT}" != "-1" ]; then
    bashio::log.info "Démarrage d'Unclutter (Masque le curseur après ${CURSOR_TIMEOUT}s)..."
    # Rend la commande non fatale
    unclutter-xfixes -idle "${CURSOR_TIMEOUT}" -root & || true
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
    # Attendre que le serveur soit prêt
    sleep 2 
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
# 5. SCRIPT JAVASCRIPT À INJECTER (Auto-Login + Kiosk Features)
# ------------------------------------------------------------------------------

# Ce script sera exécuté après le chargement de la page par la fonction REST API (voir rest_server.py)
cat > /home_assistant_kiosk.js <<EOF
(function() {
    // Variables du shell insérées ici
    const HA_USERNAME = "${HA_USERNAME}";
    const HA_PASSWORD = "${HA_PASSWORD}";
    // Le "false" sera encadré par des guillemets si la variable n'est pas "true" dans bashio::var.true
    const HA_SIDEBAR = $(if bashio::var.true "${HA_SIDEBAR}"; then echo 'true'; else echo 'false'; fi); 
    const BROWSER_REFRESH = parseInt("${BROWSER_REFRESH}");

    // --- 1. Tentative d'Auto-Login ---
    function attemptLogin() {
        const usernameInput = document.querySelector("input[name='username']");
        const passwordInput = document.querySelector("input[name='password']");
        const loginButton = document.querySelector("button[type='submit']");

        if (usernameInput && passwordInput && loginButton) {
            console.log('Tentative de connexion automatique à Home Assistant...');
            usernameInput.value = HA_USERNAME;
            passwordInput.value = HA_PASSWORD;
            
            // Simuler l'événement d'entrée pour les frameworks modernes (ex: Polymer/LitElement de HA)
            usernameInput.dispatchEvent(new Event('input', { bubbles: true }));
            passwordInput.dispatchEvent(new Event('input', { bubbles: true }));

            // Déclencher le clic (avec un petit délai pour être sûr que tout est prêt)
            setTimeout(() => {
                loginButton.click();
            }, 500);
            return true;
        }
        return false;
    }

    // --- 2. Injection des fonctionnalités Kiosque après le Login/Chargement ---
    function injectKioskFeatures() {
        // Cacher la Sidebar de Home Assistant si configuré
        if (HA_SIDEBAR === false) {
             try {
                const main = document.querySelector('home-assistant-main');
                if (main && main.shadowRoot) {
                    const sidebar = main.shadowRoot.querySelector('ha-sidebar');
                    if (sidebar) {
                        sidebar.style.display = 'none';
                        console.log('HA Sidebar cachée par script.');
                    }
                }
            } catch (e) { console.error('Erreur en cachant la sidebar:', e); }
        }

        // Gestion du Refresh Automatique
        if (BROWSER_REFRESH > 0 && !window.ha_refresh_id) {
            window.ha_refresh_id = setInterval(() => {
                console.log('Rafraîchissement automatique du navigateur...');
                window.location.reload();
            }, BROWSER_REFRESH * 1000);
            console.log('Rafraîchissement automatique configuré pour ' + BROWSER_REFRESH + ' secondes.');
        }
    }

    // Exécution de la séquence : Tente la connexion, sinon injecte les features
    // On met tout dans un timeout pour s'assurer que l'iframe HA a eu le temps de charger.
    setTimeout(() => {
        if (!attemptLogin()) {
            // Si la connexion n'est pas nécessaire (déjà connecté), injecter les features
            injectKioskFeatures();
        }
    }, ${LOGIN_DELAY} * 1000); // Utiliser le délai de login initial
})();
EOF

# ------------------------------------------------------------------------------
# 6. DÉMARRAGE DU NAVIGATEUR ET BOUCLE DE SURVEILLANCE
# ------------------------------------------------------------------------------

# Vérification du mode DEBUG
if bashio::var.true "${DEBUG_MODE}"; then
    bashio::log.warning "Mode Debug activé. Le navigateur n'est pas lancé. Le serveur Xorg tourne."
    while true; do sleep 30; done
fi

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
    
    # Attendre que la fenêtre Firefox se lance et se stabilise
    sleep 5
    
    # --- APPEL À L'API REST POUR INJECTER LE JAVASCRIPT ---
    if [ -f /rest_server.py ]; then
        bashio::log.info "Injection du script JS (Auto-Login/Kiosque) via API REST..."
        # On utilise un petit délai pour s'assurer que Firefox est prêt pour l'injection xdotool
        sleep 1 
        curl -s -X POST "http://127.0.0.1:${REST_PORT}/url_command" \
            -H "Content-Type: application/json" \
            -d "{\"command\":\"exec_js\",\"authorization_token\":\"${REST_AUTH_TOKEN}\"}"
        bashio::log.info "Injection terminée."
    fi

    # Attendre que Firefox se termine.
    wait $FIREFOX_PID
    
    # Si on arrive ici, Firefox a quitté ou a crashé
    bashio::log.error "Firefox a quitté ou a crashé (Exit code $?). Redémarrage dans 5 secondes..."
    sleep 5
    # Nettoyage préventif avant relance (anti-lock)
    rm -f "${PROFILE_DIR}/lock" "${PROFILE_DIR}/.parentlock"
done
