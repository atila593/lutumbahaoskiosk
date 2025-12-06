# Fichier d'exemple pour rest_server.py - Ajout de la commande 'exec_js'
import cherrypy
import subprocess
import os
import time

# Constantes et configurations
REST_PORT = int(os.environ.get('REST_PORT', 8080))
REST_AUTH_TOKEN = os.environ.get('REST_AUTHORIZATION_TOKEN', '')
FIREFOX_CLASS = "firefox" # Le nom de la classe de fenêtre pour xdotool
JS_INJECTION_FILE = "/home_assistant_kiosk.js" # Fichier généré dans run.sh

class KioskController(object):
    @cherrypy.expose
    @cherrypy.tools.json_in()
    def url_command(self):
        """
        Exécute une commande de navigateur (refresh, load_url, exec_js)
        """
        data = cherrypy.request.json
        command = data.get('command')
        url = data.get('url')
        
        # Vérification du jeton d'authentification
        if REST_AUTH_TOKEN and data.get('authorization_token') != REST_AUTH_TOKEN:
            cherrypy.response.status = 401
            return {"status": "error", "message": "Jeton d'autorisation invalide."}

        if command == 'refresh':
            subprocess.run(['xdotool', 'search', '--onlyvisible', '--class', FIREFOX_CLASS, 'key', 'F5'])
            return {"status": "ok", "message": "Commande de rafraîchissement envoyée."}
        
        elif command == 'load_url' and url:
            # Firefox ne prend pas en charge l'ouverture de nouvelles URL via xdotool facilement.
            # La façon la plus simple est de forcer une nouvelle instance, ou de relancer le Kiosque
            # Si le navigateur est en mode Kiosk, il peut être préférable de relancer le conteneur ou d'utiliser le serveur REST
            # pour redémarrer l'add-on, mais on va tenter de relancer le Kiosque pour l'URL cible.
            bashio_log("Tentative de changement d'URL n'est pas supportée facilement en mode Kiosk Firefox.")
            return {"status": "error", "message": "Le changement d'URL n'est pas implémenté de manière fiable pour Firefox Kiosk."}

        elif command == 'exec_js':
            try:
                # 1. Lire le script JS à injecter
                with open(JS_INJECTION_FILE, 'r') as f:
                    js_code = f.read()

                # 2. Copier le code dans le presse-papiers
                # NOTE: L'add-on doit avoir 'xclip' installé dans le Dockerfile
                process = subprocess.Popen(['xclip', '-selection', 'clipboard'], stdin=subprocess.PIPE)
                process.communicate(input=js_code.encode('utf-8'))
                
                # 3. Trouver la fenêtre Firefox
                window_id = subprocess.check_output(['xdotool', 'search', '--onlyvisible', '--class', FIREFOX_CLASS]).decode().strip().split('\n')
                if not window_id:
                    return {"status": "error", "message": "Fenêtre Firefox non trouvée."}

                # 4. Exécuter l'injection (Ouvre la console, colle le script, Entrée, Ferme la console)
                subprocess.run(['xdotool', 'windowfocus', '--sync', window_id[0], 
                                'key', '--delay', '200', 'control+shift+k', 
                                'key', '--delay', '100', 'control+v', # Coller depuis le presse-papiers
                                'key', 'Return', 
                                'key', 'Escape'], 
                                stderr=subprocess.DEVNULL) # Ignorer les erreurs d'injection

                return {"status": "ok", "message": "Script JS injecté (inclut auto-login/refresh/sidebar)."}

            except FileNotFoundError:
                return {"status": "error", "message": "Fichier d'injection JS non trouvé."}
            except Exception as e:
                return {"status": "error", "message": f"Erreur lors de l'injection JS: {e}"}

        # Commande pour l'écran (non modifiée)
        elif command == 'screen_on':
            subprocess.run(['xset', 'dpms', 'force', 'on'])
            return {"status": "ok", "message": "Écran allumé."}
        elif command == 'screen_off':
            subprocess.run(['xset', 'dpms', 'force', 'off'])
            return {"status": "ok", "message": "Écran éteint."}
        # Autres commandes (non modifiées)...

        # Commande par défaut si non reconnue
        else:
            cherrypy.response.status = 400
            return {"status": "error", "message": "Commande inconnue."}


def bashio_log(message):
    # Simuler bashio::log.info pour l'environnement Python
    print(f"[INFO] {message}")


if __name__ == '__main__':
    bashio_log(f"Démarrage du serveur REST sur le port {REST_PORT}...")
    
    # Configuration du serveur CherryPy
    cherrypy.config.update({
        'server.socket_host': '0.0.0.0',
        'server.socket_port': REST_PORT,
        'engine.autoreload_on': False,
        'log.screen': True,
        'request.dispatch': cherrypy.dispatch.MethodDispatcher(),
        '/': {
            'tools.sessions.on': False,
        }
    })
    
    cherrypy.tree.mount(KioskController(), '/', config=None)
    
    try:
        cherrypy.engine.start()
        # Garder le thread principal en vie
        cherrypy.engine.block()
    except KeyboardInterrupt:
        bashio_log("Arrêt du serveur REST.")
        cherrypy.engine.stop()
