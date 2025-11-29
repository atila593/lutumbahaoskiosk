import os
import asyncio
from aiohttp import web
import re
import logging
import sys
import json
import contextlib

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
REST_IP = "127.0.0.1" # Only listen on localhost for security
BROWSER_NAME = "lutumba" # Name of the browser executable

# Command to execute (uses 'ps' to find the command name)
BROWSER_COMMAND = f'pkill -f "{BROWSER_NAME}"'

# Default command to turn display on (must be in the path)
DISPLAY_ON_COMMAND = "xset"
# Default command to turn display off (must be in the path)
DISPLAY_OFF_COMMAND = "xset"
# Default command to check display status (must be in the path)
DISPLAY_STATUS_COMMAND = "xset"

# --------------------------------------------------------------------------
# Utility Functions
# --------------------------------------------------------------------------

async def execute_command(cmd, timeout=5, shell=False):
    """Execute shell command and return output."""
    logging.debug(f"[execute_command] Running command: {cmd}")
    try:
        proc = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            shell=shell
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        logging.debug(f"[execute_command] Command stdout: {stdout.decode()}")
        if stderr:
            logging.error(f"[execute_command] Command stderr: {stderr.decode()}")
        return proc.returncode, stdout.decode(), stderr.decode()
    except asyncio.TimeoutError:
        logging.error(f"[execute_command] Command timed out after {timeout} seconds: {cmd}")
        # Try to terminate the process group to kill all spawned children
        with contextlib.suppress(ProcessLookupError):
            os.killpg(os.getpgid(proc.pid), 9)
        return 1, "", f"Command timed out after {timeout} seconds: {cmd}"
    except Exception as e:
        logging.error(f"[execute_command] Failed to run command {cmd}: {e}")
        return 1, "", str(e)


def restart_browser(url=None):
    """Stop the browser process and restart it with a new URL if provided."""
    logging.info(f"[restart_browser] Stopping {BROWSER_NAME}...")

    # Send a SIGTERM (15) to the browser process to ensure graceful shutdown
    # This assumes the main browser process is the one listening to the kill signal
    returncode, _, _ = asyncio.run(execute_command(f'{BROWSER_COMMAND} -TERM', timeout=5))

    if url:
        logging.info(f"[restart_browser] Launching {BROWSER_NAME} with new URL: {url}")
        # NOTE: This uses asyncio.create_subprocess_shell to launch the browser
        # but does NOT wait for it, allowing the API call to complete.
        asyncio.create_task(
            asyncio.create_subprocess_shell(
                f'{BROWSER_NAME} "{url}"',
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL
            )
        )
        # Restore DPMS to avoid screen blanking on next refresh
        asyncio.run(execute_command(f'{DISPLAY_ON_COMMAND} dpms force on', timeout=1))

    return returncode == 0

# --------------------------------------------------------------------------
# Middleware and Handlers
# --------------------------------------------------------------------------

@web.middleware
async def auth_middleware(request, handler):
    """Authenticate requests if a token is configured."""
    if REST_BEARER_TOKEN:
        auth_header = request.headers.get("Authorization")
        if not auth_header or auth_header != f"Bearer {REST_BEARER_TOKEN}":
            logging.warning("[auth_middleware] Authorization failed for request.")
            return web.json_response({"success": False, "error": "Unauthorized"}, status=401)
    
    return await handler(request)

@web.middleware
async def handle_404_middleware(request, handler):
    """Handle 404/Not Found errors gracefully."""
    try:
        response = await handler(request)
        logging.debug(f"[handle_404_middleware] Response type: {type(response)}")
        if isinstance(response, web.Response):
            return response
        return response
    except web.HTTPNotFound:
        logging.error(f"[main] Invalid endpoint requested: {request.path}")
        return web.json_response({"success": False, "error": f"Requested endpoint {request.path} is invalid"}, status=404)

async def handle_launch_url(request):
    """Handle /launch_url command (restarts browser with new URL)."""
    try:
        data = await request.json()
        url = data.get("url")
        if not url:
            return web.json_response({"success": False, "error": "URL parameter missing"}, status=400)

        logging.info(f"[/launch_url] Received request to launch URL: {url}")
        
        # Strip browser-mod ID if present (optional)
        url = re.sub(r'#.*$', '', url)
        if '?' in url:
            url += '&'
        else:
            url += '?'
        url += 'browser_mod=haos_kiosk'
        
        success = restart_browser(url=url)

        return web.json_response({"success": success, "url": url})
    except Exception as e:
        logging.error(f"[/launch_url] Error processing request: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_refresh_browser(request):
    """Handle /refresh_browser command (restarts browser with current URL)."""
    logging.info("[/refresh_browser] Received request to refresh browser.")
    
    # We restart the browser without providing a URL, it will reload the default/last URL
    success = restart_browser(url=None)

    return web.json_response({"success": success})

async def handle_is_display_on(request):
    """Handle /is_display_on command (checks DPMS status)."""
    logging.info("[/is_display_on] Received request to check display status.")
    
    returncode, stdout, _ = await execute_command(f"{DISPLAY_STATUS_COMMAND} -q dpms", timeout=1)

    if returncode == 0 and "Monitor is On" in stdout:
        return web.json_response({"success": True, "status": "on"})
    elif returncode == 0 and "Monitor is Off" in stdout:
        return web.json_response({"success": True, "status": "off"})
    
    # Fallback/error case
    return web.json_response({"success": False, "error": "Could not determine display status", "stdout": stdout})

async def handle_display_on(request):
    """Handle /display_on command (turns display on)."""
    logging.info("[/display_on] Received request to turn display on.")
    
    try:
        # Default DPMS command: force on
        cmd = f"{DISPLAY_ON_COMMAND} dpms force on"
        
        # Check for optional timeout parameter to re-enable screen blanking
        try:
            data = await request.json()
            timeout = data.get("timeout")
            if timeout is not None and int(timeout) > 0:
                logging.info(f"[/display_on] Re-enabling screen blanking with timeout: {timeout} seconds.")
                # Set the standby, suspend, and off timeouts to the new value
                cmd = f"{DISPLAY_ON_COMMAND} +dpms; {DISPLAY_ON_COMMAND} dpms {timeout} {timeout} {timeout}"
        except json.JSONDecodeError:
            # No JSON data provided, continue with default 'force on' command
            pass
            
        returncode, stdout, stderr = await execute_command(cmd)

        return web.json_response({"success": returncode == 0, "stdout": stdout, "stderr": stderr})
    except Exception as e:
        logging.error(f"[/display_on] Error processing request: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)


async def handle_display_off(request):
    """Handle /display_off command (turns display off)."""
    logging.info("[/display_off] Received request to turn display off.")
    
    # DPMS command: force off
    cmd = f"{DISPLAY_OFF_COMMAND} dpms force off"
    
    returncode, stdout, stderr = await execute_command(cmd)
    
    return web.json_response({"success": returncode == 0, "stdout": stdout, "stderr": stderr})

async def handle_current_processes(request):
    """Handle /current_processes command (returns running processes)."""
    logging.info("[/current_processes] Received request for current processes.")
    
    # Use 'ps' to get a list of running processes in the container
    cmd = "ps aux"
    
    returncode, stdout, stderr = await execute_command(cmd)
    
    if returncode == 0:
        return web.json_response({"success": True, "processes": stdout.strip().split('\n')})
    else:
        return web.json_response({"success": False, "error": "Could not retrieve process list", "stderr": stderr})

async def handle_xset(request):
    """Handle /xset command (runs arbitrary xset commands)."""
    try:
        data = await request.json()
        args = data.get("args")
        if not args:
            return web.json_response({"success": False, "error": "Args parameter missing"}, status=400)

        logging.info(f"[/xset] Received request to run xset with args: {args}")
        
        cmd = f"xset {args}"
        returncode, stdout, stderr = await execute_command(cmd)

        return web.json_response({"success": returncode == 0, "stdout": stdout, "stderr": stderr})
    except Exception as e:
        logging.error(f"[/xset] Error processing request: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_run_command(request):
    """Handle /run_command command (runs arbitrary shell commands)."""
    if not ALLOW_USER_COMMANDS:
        return web.json_response({"success": False, "error": "Arbitrary commands are disabled. Set allow_user_commands: true in configuration."}, status=403)
        
    try:
        data = await request.json()
        cmd = data.get("cmd")
        cmd_timeout = int(data.get("cmd_timeout", 5))
        if not cmd:
            return web.json_response({"success": False, "error": "Command parameter missing"}, status=400)

        logging.warning(f"[/run_command] Running UNRESTRICTED command: {cmd} with timeout {cmd_timeout}s")
        
        returncode, stdout, stderr = await execute_command(cmd, timeout=cmd_timeout, shell=True)

        return web.json_response({"success": returncode == 0, "stdout": stdout, "stderr": stderr, "returncode": returncode})
    except Exception as e:
        logging.error(f"[/run_command] Error processing request: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_run_commands(request):
    """Handle /run_commands command (runs a list of arbitrary shell commands)."""
    if not ALLOW_USER_COMMANDS:
        return web.json_response({"success": False, "error": "Arbitrary commands are disabled. Set allow_user_commands: true in configuration."}, status=403)

    try:
        data = await request.json()
        cmds = data.get("cmds")
        cmd_timeout = int(data.get("cmd_timeout", 5))

        if not cmds or not isinstance(cmds, list):
            return web.json_response({"success": False, "error": "Cmds parameter missing or not a list"}, status=400)

        results = []
        overall_success = True
        
        for cmd in cmds:
            logging.warning(f"[/run_commands] Running UNRESTRICTED command: {cmd} with timeout {cmd_timeout}s")
            returncode, stdout, stderr = await execute_command(cmd, timeout=cmd_timeout, shell=True)
            
            if returncode != 0:
                overall_success = False

            results.append({
                "cmd": cmd,
                "success": returncode == 0,
                "returncode": returncode,
                "stdout": stdout,
                "stderr": stderr
            })

        return web.json_response({"success": overall_success, "results": results})

    except Exception as e:
        logging.error(f"[/run_commands] Error processing request: {e}")
        return web.json_response({"success": False, "error": str(e)}, status=500)


@web.middleware
async def handle_request_errors(request, handler):
    """A generic error handler for all requests."""
    try:
        return await handler(request)
    except Exception as e:
        logging.error(f"[/main] Unhandled exception in request handler for {request.path}: {e}", exc_info=True)
        return web.json_response(
            {"success": False, "error": f"Internal server error: {e}"},
            status=500
        )

async def main():
    """Run REST server."""
    app = web.Application(middlewares=[auth_middleware, handle_404_middleware])
    app.router.add_post("/launch_url", handle_launch_url)
    app.router.add_post("/refresh_browser", handle_refresh_browser)
    app.router.add_get("/is_display_on", handle_is_display_on)
    app.router.add_post("/display_on", handle_display_on)
    app.router.add_post("/display_off", handle_display_off)
    app.router.add_get("/current_processes", handle_current_processes)
    app.router.add_post("/xset", handle_xset)
    app.router.add_post("/run_command", handle_run_command)
    app.router.add_post("/run_commands", handle_run_commands)
    logging.info(f"[main] Starting REST server on http://127.0.0.1:{REST_PORT}")
    runner = web.AppRunner(app)
    await runner.setup()
    try:
        site = web.TCPSite(runner, REST_IP, REST_PORT)
        await site.start()
        # Keep the main coroutine running forever
        await asyncio.Future()
    finally:
        await runner.cleanup()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logging.info("[main] REST server stopped by keyboard interrupt (Ctrl+C).")
