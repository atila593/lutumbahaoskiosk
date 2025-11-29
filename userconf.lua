--[[
Add-on: HAOS Lutumba Kiosk
File: userconf.lua pour le navigateur Lutumba (configuration Kiosk)
Version: 1.1.1

Ce fichier de configuration Lua gère les fonctionnalités suivantes :
    - Définition de la fenêtre du navigateur en plein écran.
    - Application du niveau de zoom à la valeur de $ZOOM_LEVEL (par défaut 100%).
    - Chargement de chaque URL en mode 'passthrough' pour permettre la saisie de texte sans déclencher les commandes du navigateur.
    - Connexion automatique à Home Assistant via $HA_USERNAME et $HA_PASSWORD.
    - Redéfinition de la touche pour revenir au mode normal (utilisé pour les commandes) du mode 'passthrough' à 'Ctl-Alt-Esc'
      (au lieu de simplement 'Esc') pour éviter les retours involontaires au mode normal et l'activation de commandes non désirées.
    - Ajout de la liaison <Control-r> pour recharger l'écran du navigateur (dans tous les modes).
    - Empêche l'affichage de la ligne d'état '--PASS THROUGH--' lors du passage en mode 'passthrough'.
    - Configuration d'un rafraîchissement périodique du navigateur toutes les $BROWSWER_REFRESH secondes (désactivé si 0).
      NOTE: Ceci est important car les messages de la console peuvent parfois masquer les tableaux de bord.
    - Autorise un $ZOOM_LEVEL configurable.
    - Préfère le thème de couleur sombre pour les sites Web qui le supportent si la variable d'environnement $DARK_MODE est vraie (par défaut à true).
    - Définit la visibilité de la barre latérale de Home Assistant à l'aide de la variable d'environnement $HA_SIDEBAR.
    - Définit l'identifiant 'browser_mod-browser-id' à la valeur fixe 'haos_kiosk'.
    - Si le clavier virtuel est utilisé, masque le clavier après le (re)chargement de la page.
    - Empêche la restauration de session en surchargeant 'session.restore'.
]]

-- ---------------------------------------------------------------------------
-- Charger les modules de configuration Luakit/Lutumba
local awful = require("awful")
local luakit = require("luakit")
local modes = require("modes")
local msg = require("lousy.util.message")

-- Charger les variables d'environnement définies dans run.sh
local ha_username = awful.util.getenv("HA_USERNAME")
local ha_password = awful.util.getenv("HA_PASSWORD")
local login_delay = awful.util.getenv("LOGIN_DELAY")
local ha_sidebar = awful.util.getenv("HA_SIDEBAR")
local zoom_level = awful.util.getenv("ZOOM_LEVEL")
local dark_mode = awful.util.getenv("DARK_MODE").lower() == "true"
local browser_refresh = tonumber(awful.util.getenv("BROWSER_REFRESH"))
local onscreen_keyboard = awful.util.getenv("ONSCREEN_KEYBOARD").lower() == "true"

-- Touche personnalisée pour quitter le mode passthrough/entrer en mode normal
local new_escape_key = "<Control-Alt-Escape>"
local ha_url_regex = awful.util.escape_pattern(awful.util.getenv("HA_URL")) .. "/"

-- ---------------------------------------------------------------------------
-- Configuration de la barre latérale Home Assistant
-- ---------------------------------------------------------------------------
if ha_sidebar == "hidden" then
    -- Injection de code CSS pour masquer la barre latérale et l'espace réservé
    luakit.add_css([[
        /* Hide sidebar and all space it consumes */
        :host {
            --sidebar-width: 0px !important;
            --ha-left-align: 0px !important;
            --app-drawer-width: 0px !important;
            --mdc-icon-size: 0px !important;
        }

        /* Hides the bottom navigation bar and the space it takes */
        @media (max-width: 800px) {
            :host {
                --ha-app-layout-padding-bottom: 0px !important;
            }
            .nav {
                display: none !important;
            }
        }
    ]])
elseif ha_sidebar == "top" then
    -- Force la barre latérale en haut de l'écran (si elle est affichée)
    luakit.add_css([[
        /* Hides the bottom navigation bar and the space it takes */
        @media (max-width: 800px) {
            :host {
                --ha-app-layout-padding-bottom: 0px !important;
            }
            .nav {
                display: none !important;
            }
        }
    ]])
end

-- ---------------------------------------------------------------------------
-- Configuration du thème sombre (Dark Mode)
-- ---------------------------------------------------------------------------
if dark_mode then
    -- Préfère le thème sombre
    luakit.set_preferred_color_scheme("dark")
end

-- ---------------------------------------------------------------------------
-- Configuration de la fenêtre et des modes
-- ---------------------------------------------------------------------------
-- Initialisation de la fenêtre en plein écran
luakit.set_default("default_window_settings", {
    fullscreen = true,
})

-- Définir le mode par défaut pour les nouvelles fenêtres comme 'passthrough'
luakit.set_default("default_mode", "passthrough")

-- ---------------------------------------------------------------------------
-- Événements après le chargement d'une URL
-- ---------------------------------------------------------------------------
luakit.signals.connect("uri-changed", function (w, uri)
    -- Appliquer le niveau de zoom
    w:zoom(tonumber(zoom_level) / 100.0)

    -- Configurer l'identifiant 'browser_mod-browser-id'
    w.web_view:eval_js("localStorage.setItem('browser_mod-browser-id', 'haos_kiosk')", { source = "browser_mod.js", no_return = true })

    -- Masquer le clavier virtuel si l'option est activée
    if onscreen_keyboard then
        -- Envoie une commande D-Bus pour masquer le clavier Onboard
        awful.util.spawn_with_shell("dbus-send --type=method_call --dest=org.onboard.Onboard /org/onboard/Onboard/Keyboard org.onboard.Onboard.Keyboard.Hide")
    end

    -- -----------------------------------------------------------------------
    -- Auto-connexion à Home Assistant
    -- -----------------------------------------------------------------------
    -- Vérifie si l'URL correspond à la page de connexion de Home Assistant
    if uri:match(ha_url_regex .. ".*login") then
        msg.info("Tentative de connexion automatique à Home Assistant...")
        local js_login = string.format([[
            setTimeout(function() {
                var usernameField = document.querySelector("input[type='text']");
                var passwordField = document.querySelector("input[type='password']");
                var loginButton = document.querySelector("button[type='submit']");

                if (usernameField && passwordField && loginButton) {
                    usernameField.value = "%s";
                    passwordField.value = "%s";
                    loginButton.click();
                } else {
                    console.error("Éléments de connexion non trouvés après le délai.");
                }
            }, %s);
        ]], ha_username, ha_password, login_delay * 1000)

        -- Injecte le script de connexion
        w.web_view:eval_js(js_login, { source = "auto_login.js", no_return = true })
    end
    -- -----------------------------------------------------------------------
    -- Rafraîchissement périodique du navigateur
    -- -----------------------------------------------------------------------
    if browser_refresh > 0 and uri:match(ha_url_regex) then
        local js_refresh = string.format([[
            if (window.ha_refresh_id) {
                clearInterval(window.ha_refresh_id);
                console.log("Rafraîchissement précédent effacé.");
            }
            window.ha_refresh_id = setInterval(function() {
                console.log("Rafraîchissement automatique du navigateur...");
                window.location.reload();
            }, %d);
            window.addEventListener('beforeunload', function() {
                clearInterval(window.ha_refresh_id);
            });
        ]], browser_refresh * 1000)

        -- Injecte le script de rafraîchissement dans la webview
        w.web_view:eval_js(js_refresh, { source = "auto_refresh.js", no_return = true })  -- Exécute le script de rafraîchissement
        msg.info("Injection de l'intervalle de rafraîchissement : %s secondes", browser_refresh)  -- DEBUG
    end

end)

-- -----------------------------------------------------------------------
-- Surcharge des fonctions de session pour empêcher la restauration
-- -----------------------------------------------------------------------
local session = require("session")

function session.restore(file_name)
    msg.info("Restauration de session désactivée.")
    return false
end

-- -----------------------------------------------------------------------
-- Redéfinition des raccourcis clavier
-- -----------------------------------------------------------------------
-- Redéfinir <Esc> à 'new_escape_key' (e.g., <Ctl-Alt-Esc>) pour quitter le mode actuel et entrer en mode normal
modes.remove_binds({"passthrough"}, {"<Escape>"})
modes.add_binds("passthrough", {
    {new_escape_key, "Switch to normal mode", function(w)
        w:set_prompt()
        w:set_mode() -- Utiliser ceci si 'default_mode' n'est pas redéfini car la valeur par défaut est "normal"
--        w:set_mode("normal") -- Utiliser ceci si 'default_mode' est redéfini [Option#3]
     end}
}
)
-- Ajouter la liaison <Control-r> dans tous les modes pour recharger la page
modes.add_binds("all", {
    { "<Control-r>", "reload page", function (w) w:reload() end },
    })

-- Effacer la ligne de commande lors de l'entrée en mode passthrough au lieu d'afficher '-- PASS THROUGH --'
modes.get_modes()["passthrough"].enter = function(w)
    w:set_prompt()            -- Effacer l'invite de commande
    w:set_input()             -- Activer le champ de saisie (e.g., URL...
end
