import os
import asyncio
from aiohttp import web
import re
import logging
import sys
import json
import contextlib
import subprocess 

# Configure logging to stdout to match bashio::log format
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
#    level=logging.DEBUG,
    format="[%(asctime)s] %(levelname)s: [%(filename)s] %(message)s",
    datefmt="%H:%M:%S"
)

# Get environment variables (set in run.sh)
ALLOW_USER_COMMANDS = os.getenv("ALLOW_USER_COMMANDS").lower() == "true"
SCREEN_TIMEOUT = os.getenv("SCREEN_TIMEOUT")
REST_PORT = os.getenv("REST_PORT")
REST_BEARER_TOKEN = os.getenv("REST_BEARER_TOKEN")
REST_IP = "127.0.0.1" # Force listening on localhost

# Define Lutumba's process name (used to find the PID)
BROWSER_PID = 0
# 🚀 MODIFICATION CRUCIALE pour Lutumba :
BROWSER_NAME = "lutumba" 
LOG_LEVEL = logging.DEBUG if os.getenv("DEBUG_MODE").lower() == "true" else logging.INFO
logging.getLogger().setLevel(LOG_LEVEL)

################################################################################
# Utility Functions
################################################################################
def get_browser_pid():
    """Finds the PID of the running browser process."""
    global BROWSER_PID
    try:
        # Use pgrep to find the PID of the browser.
        # We use -x to match the full process name exactly.
        pids = subprocess_wrapper(["pgrep", "-x", BROWSER_NAME])
        if pids and pids.strip():
            # Get the first PID found
            BROWSER_PID = pids.strip().split('\n')[0]
            logging.debug(f"[get_browser_pid] Found PID {BROWSER_PID} for {BROWSER_NAME}")
            return int(BROWSER_PID)
        
        BROWSER_PID = 0
        logging.debug(f"[get_browser_pid] PID not found for {BROWSER_NAME}. Output: {pids.strip()}")
        return 0

    except Exception as e:
        logging.error(f"[get_browser_pid] Error finding PID for {BROWSER_NAME}: {e}")
        BROWSER_PID = 0
        return 0

def subprocess_wrapper(cmd, timeout=5, shell=False):
    """Executes a subprocess command."""
    try:
        # We need to capture the output, and timeout is a good safety measure
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            shell=shell
        )
        if result.returncode != 0 and result.stderr:
            # Log error but still return stdout for potential partial results
            logging.warning(f"[subprocess_wrapper] Command '{' '.join(cmd)}' failed with error: {result.stderr.strip()}")
        
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        logging.error(f"[subprocess_wrapper] Command '{' '.join(cmd)}' timed out after {timeout} seconds.")
        return ""
    except FileNotFoundError:
        logging.error(f"[subprocess_wrapper] Command '{' '.join(cmd)}' not found. Is it installed and in PATH?")
        return ""
    except Exception as e:
        logging.error(f"[subprocess_wrapper] An error occurred executing '{' '.join(cmd)}': {e}")
        return ""


################################################################################
# REST API Handlers
################################################################################

async def handle_launch_url(request):
    """Launches a URL in the browser using xdotool."""
    try:
        data = await request.json()
        url = data.get("url")
        if not url:
            return web.json_response({"success": False, "error": "Missing 'url' parameter"}, status=400)
        
        if get_browser_pid() == 0:
            return web.json_response({"success": False, "error": f"{BROWSER_NAME} is not running (PID not found)"}, status=500)

        # La méthode la plus fiable pour un navigateur GTK/WebKit (Lutumba) est de simuler Ctrl+L
        # pour forcer le focus sur la barre d'adresse et de taper l'URL.
        
        logging.info(f"[handle_launch_url] Attempting to launch URL: {url} in {BROWSER_NAME} window")

        cmd = [
            "xdotool", 
            "search", 
            "--onlyvisible", 
            "--pid", 
            str(BROWSER_PID), 
            "--limit", 
            "1", 
            "windowfocus",
            "key", 
            "--delay", 
            "100", 
            "control+l", # Focus address bar (universal browser shortcut)
            "type", 
            "--delay", 
            "5", 
            "--clearmodifiers", 
            url, 
            "Return"
        ]
        
        subprocess_wrapper(cmd)

        return web.json_response({"success": True, "message": f"URL '{url}' launched successfully."})
        
    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON format"}, status=400)
    except Exception as e:
        logging.error(f"[handle_launch_url] An unexpected error occurred: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)


async def handle_refresh_browser(request):
    """Refreshes the browser using xdotool (Ctrl+R)."""
    try:
        if get_browser_pid() == 0:
            return web.json_response({"success": False, "error": f"{BROWSER_NAME} is not running (PID not found)"}, status=500)

        # Send Ctrl+R (reload) to the browser window
        logging.info(f"[handle_refresh_browser] Refreshing {BROWSER_NAME} via xdotool (Ctrl+R)")
        
        cmd = [
            "xdotool", 
            "search", 
            "--onlyvisible", 
            "--pid", 
            str(BROWSER_PID), 
            "--limit", 
            "1", 
            "key", 
            "--delay", 
            "100", 
            "control+r"
        ]
        subprocess_wrapper(cmd)

        return web.json_response({"success": True, "message": f"{BROWSER_NAME} refreshed successfully."})

    except Exception as e:
        logging.error(f"[handle_refresh_browser] An unexpected error occurred: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_is_display_on(request):
    """Checks the display power status using xset."""
    try:
        # Get the DPMS status (Display Power Management Signaling)
        result = subprocess_wrapper(["xset", "-q"])
        
        # Regex to find 'Monitor is On/Off'
        is_on_match = re.search(r"Monitor is (On|Off)", result)
        
        if is_on_match:
            is_on = is_on_match.group(1) == "On"
            return web.json_response({"success": True, "is_display_on": is_on, "details": result.strip()})
        else:
            # Fallback if the output format changes, assume ON by default but warn
            logging.warning(f"[handle_is_display_on] Could not parse 'Monitor is On/Off' from xset output. Assuming ON. Output: {result.strip()}")
            return web.json_response({"success": True, "is_display_on": True, "warning": "Could not parse display status from xset output. Assuming ON.", "details": result.strip()})

    except Exception as e:
        logging.error(f"[handle_is_display_on] An unexpected error occurred: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_display_on(request):
    """Turns the display on (wakes it) and optionally sets a new screen timeout."""
    try:
        data = await request.json()
        timeout = data.get("timeout")
        
        # 1. Turn display on (reset DPMS timer)
        subprocess_wrapper(["xset", "dpms", "force", "on"])
        logging.info("[handle_display_on] Display forced ON via xset dpms force on.")

        # 2. Optionally set a new timeout
        if timeout is not None:
            with contextlib.suppress(ValueError):
                timeout = int(timeout)
                if timeout >= 0:
                    subprocess_wrapper(["xset", "dpms", "0", "0", str(timeout)])
                    subprocess_wrapper(["xset", "+dpms"] if timeout > 0 else ["xset", "-dpms"])
                    logging.info(f"[handle_display_on] New screen timeout set to {timeout} seconds.")
                    return web.json_response({"success": True, "message": f"Display ON. New timeout set to {timeout}s."})
                else:
                    return web.json_response({"success": False, "error": "Timeout must be a non-negative integer."}, status=400)
        
        return web.json_response({"success": True, "message": "Display ON (DPMS reset)." if timeout is None else "Display ON. Invalid timeout format."})

    except json.JSONDecodeError:
        return web.json_response({"success": False, "error": "Invalid JSON format (optional: {\"timeout\": <seconds>})"}, status=400)
    except Exception as e:
        logging.error(f"[handle_display_on] An unexpected error occurred: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_display_off(request):
    """Turns the display off (blanks it) immediately."""
    try:
        # Force display off (blank it)
        subprocess_wrapper(["xset", "dpms", "force", "off"])
        logging.info("[handle_display_off] Display forced OFF via xset dpms force off.")
        
        return web.json_response({"success": True, "message": "Display OFF forced."})

    except Exception as e:
        logging.error(f"[handle_display_off] An unexpected error occurred: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_current_processes(
