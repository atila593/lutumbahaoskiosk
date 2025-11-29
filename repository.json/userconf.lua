--[[
Add-on: HAOS Lutumba Kiosk Display (haoslutumakiosk)
File: userconf.lua for HA minimal browser run on server
Version: 1.1.1

Code does the following:
    - Sets browser window to fullscreen
    - Sets zooms level to value of $ZOOM_LEVEL (default 100%)
    - Loads every URL in 'passthrough' mode so that you can type text as needed without triggering browser commands
    - Auto-logs in to Home Assistant using $HA_USERNAME and $HA_PASSWORD
    - Redefines key to return to normal mode (used for commands) from 'passthrough' mode to: 'Ctl-Alt-Esc'
      (rather than just 'Esc') to prevent unintended  returns to normal mode and activation of unwanted commands
    - Adds <Control-r> binding to reload browser screen (all modes)
    - Prevent printing of '--PASS THROUGH--' status line when in 'passthrough' mode
    - Set up periodic browser refresh every $BROWSWER_REFRESH seconds (disabled if 0)
      NOTE: this is important since console messages overwrite dashboards
    - Allows for configurable browser $ZOOM_LEVEL
    - Prefer dark color scheme for websites that support it if $DARK_MODE environment variable true (default to true)
    - Set Home Assistant sidebar visibility using $HA_SIDEBAR environment variables
    - Set 'browser_mod-browser-id' to fixed value 'haos_kiosk'
    - If using onscreen keyboard, hide keyboard after page (re)load
    - Prevent session restore by overloading 'session.restore
]]

-- ---------------------------------------------------------------------------
-- Libraries
-- ---------------------------------------------------------------------------
local msg = require "luakit.message"
local modes = require "luakit.modes"
local window = require "luakit.window"
local session = require "luakit.session"
local settings = require "luakit.settings"
local timer = require "lousy.timer"
local os = os
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local table = table
local pcall = pcall
local string = string
local log = luakit.message
local unique = require "luakit.unique"

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- Set the default start page/URL from the environment variable
local ha_url = os.getenv("HA_URL")
local ha_dashboard = os.getenv("HA_DASHBOARD")
local start_page = ha_url .. "/" .. ha_dashboard

-- Keys used for automatic login and mode switching
local ha_username = os.getenv("HA_USERNAME")
local ha_password = os.getenv("HA_PASSWORD")
local login_delay = tonumber(os.getenv("LOGIN_DELAY")) or 1.0
local new_escape_key = "<Control-Alt-Escape>"

-- Configurable settings from environment variables
local zoom_level = tonumber(os.getenv("ZOOM_LEVEL")) or 100
local browser_refresh = tonumber(os.getenv("BROWSER_REFRESH")) or 0
local dark_mode = os.getenv("DARK_MODE") == "true"
local ha_sidebar = os.getenv("HA_SIDEBAR") or "none"
local onscreen_keyboard = os.getenv("ONSCREEN_KEYBOARD") == "true"

-- Set a fixed 'browser_mod-browser-id' for easier control via browser_mod
settings.default.user_agent_script = string.format([[
    (function () {
        Object.defineProperty(navigator, 'userAgent', {
            value: navigator.userAgent + ' HomeAssistant-HAOS-Lutumba-Kiosk'
        });
        localStorage.setItem('browser_mod-browser-id', 'haos_kiosk');
    })();
]], ha_url)


-- ---------------------------------------------------------------------------
-- Session/Window Initialization Hooks
-- ---------------------------------------------------------------------------

-- Force fullscreen and zoom level on new windows/tabs
window.add_hook("new-window", function (w)
    -- Start in fullscreen mode
    w.fullscreen = true

    -- Set zoom level
    settings.get_user_settings(w.view).zoom_level = zoom_level / 100
end)

window.add_hook("create", function (w)
    -- Load initial URL
    w:new_tab(start_page)
end)

-- ---------------------------------------------------------------------------
-- Page Load Hooks (Login, Sidebar, Refresh)
-- ---------------------------------------------------------------------------

local function ha_login_script()
    return string.format([[
        // Auto-login script for Home Assistant
        setTimeout(function() {
            var input = document.querySelector("body > app-root > home-assistant > auth-panel > div > ha-card > ha-form > ha-textfield[type='text']");
            var password = document.querySelector("body > app-root > home-assistant > auth-panel > div > ha-card > ha-form > ha-textfield[type='password']");
            var loginButton = document.querySelector("body > app-root > home-assistant > auth-panel > div > ha-card > ha-form > ha-progress-button");

            if (input && password && loginButton) {
                input.value = '%s';
                password.value = '%s';
                loginButton.click();
                console.log('HA Kiosk: Auto-login attempted.');
            }
        }, %d);
    ]], ha_username, ha_password, login_delay * 1000)
end

local function sidebar_hide_script()
    return string.format([[
        // Hide sidebar script for Home Assistant
        setTimeout(function() {
            var ha_root = document.querySelector("home-assistant");
            if (ha_root) {
                ha_root.dispatchEvent(new Event('hass-toggle-menu', {bubbles: true, composed: true}));
                console.log('HA Kiosk: Sidebar toggle attempted.');
            }
        }, 1000);
    ]])
end

local function hide_keyboard_script()
    return [[
        // Hide Onboard keyboard after page load
        dbus.session.emit('org.onboard.Onboard.Keyboard', 'Hide');
        console.log('HA Kiosk: Onscreen keyboard hide attempted.');
    ]]
end

window.add_hook("page-load-finished", function (w)
    local v = w.view

    -- 1. Auto-login
    if string.find(v.uri, ha_url) and not string.find(v.uri, "home-assistant.io") then
        if string.find(v.uri, "auth/login") then
            -- Inject login script
            v:eval_js(ha_login_script(), { source = "ha_login.js", no_return = true })
            msg.info("Injecting HA auto-login script: %s", v.uri)
        else
            -- 2. Sidebar visibility (only after successful login)
            if ha_sidebar == "hidden" or ha_sidebar == "top" then
                v:eval_js(sidebar_hide_script(), { source = "ha_sidebar_hide.js", no_return = true })
                msg.info("Injecting HA sidebar hide script: %s", v.uri)
            end
        end
    end

    -- 3. Onscreen Keyboard
    if onscreen_keyboard then
        -- This relies on the system setup being correct.
        -- We will not inject this script unless needed.
        -- v:eval_js(hide_keyboard_script(), { source = "keyboard_hide.js", no_return = true })
    end
end)

-- ---------------------------------------------------------------------------
-- Global Settings
-- ---------------------------------------------------------------------------

-- Always start in passthrough mode (allows typing in HA password field)
settings.default.default_mode = "passthrough"

-- Prevent session restore to always load the configured URL
function session.restore(name, cb)
    -- Do nothing, effectively preventing the session restore.
    log.info("Session restore prevented.")
    cb()
end

-- Use dark mode if configured
if dark_mode then
    settings.default.color_scheme = "dark"
end

-- ---------------------------------------------------------------------------
-- Browser Refresh Timer
-- ---------------------------------------------------------------------------

if browser_refresh > 0 then
    -- Inject the browser refresh logic after the window is created
    window.add_hook("create", function (w)
        local v = w.view
        
        if string.find(start_page, ha_url) then
            -- This JavaScript will run inside the webview content
            local js_refresh = string.format([[
                var browser_refresh_interval = %d;
                if (browser_refresh_interval > 0) {
                    window.ha_refresh_id = setInterval(function() {
                        window.location.reload(true);
                        console.log('HA Kiosk: Auto-refresh triggered.');
                    }, browser_refresh_interval * 1000);
                }
                
                // Clear interval when navigating away from the refresh page
                window.addEventListener('beforeunload', function() {
                    clearInterval(window.ha_refresh_id);
                });
            ]], browser_refresh)

            -- Inject refresh script into the webview
            v:eval_js(js_refresh, { source = "auto_refresh.js", no_return = true })  -- Execute the refresh script
            msg.info("Injecting refresh interval: %s", v.uri)  -- DEBUG
        end

    end)
end

-- ---------------------------------------------------------------------------
-- Key Bindings
-- ---------------------------------------------------------------------------
-- Redefine <Esc> to 'new_escape_key' (e.g., <Ctl-Alt-Esc>) to exit current mode and enter normal mode
modes.remove_binds({"passthrough"}, {"<Escape>"})
modes.add_binds("passthrough", {
    {new_escape_key, "Switch to normal mode", function(w)
        w:set_prompt()
        w:set_mode() -- Use this if not redefining 'default_mode' since defaults to "normal"
     end}
}
)
-- Add <Control-r> binding in all modes to reload page
modes.add_binds("all", {
    { "<Control-r>", "reload page", function (w) w:reload() end },
    })

-- Clear the command line when entering passthrough instead of typing '-- PASS THROUGH --'
modes.get_modes()["passthrough"].enter = function(w)
    w:set_prompt()            -- Clear the command line prompt
    w:set_input()             -- Activate the input field (e.g., URL bar) if needed
end
