# HAOS Lutumba Kiosk

Affichez les tableaux de bord Home Assistant en mode kiosque directement sur votre serveur HAOS.

## Description

Lance le serveur X-Windows sur le serveur HAOS local, suivi du gestionnaire de fenêtres OpenBox et du navigateur **Lutumba**.
Les interactions standard avec la souris et le clavier devraient fonctionner automatiquement. Prend en charge les écrans tactiles (y compris le clavier à l'écran) et la rotation de l'écran.

Comprend une API REST qui peut être utilisée pour contrôler l'état de l'affichage et pour envoyer de nouvelles URL (par exemple, des tableaux de bord) au navigateur kiosque.

Vous pouvez appuyer sur `Ctrl-R` à tout moment pour rafraîchir le navigateur.

**NOTE IMPORTANTE :** Vous devez entrer votre nom d'utilisateur et votre mot de passe Home Assistant dans l'onglet *Configuration* pour que l'add-on puisse démarrer.

**NOTE :** L'add-on nécessite un affichage valide et connecté pour démarrer. Si l'affichage n'apparaît pas, essayez de redémarrer et de relancer l'add-on avec l'affichage attaché.

**Note sur le navigateur :** Le navigateur **Lutumba** est lancé en mode kiosque (*passthrough*).
Pour revenir au mode *normal* (similaire au mode commande dans `vi`), appuyez sur `Ctrl-Alt-Esc`.
Vous pouvez ensuite revenir au mode *passthrough* en appuyant sur `Ctrl-Z` ou entrer en mode *insertion* en appuyant sur `i`.
En général, il est recommandé de rester en mode `passthrough`.

**NOTE :** Devrait prendre en charge toute souris, écran tactile, pavé numérique et pavé tactile standard tant que leur numéro `/dev/input/eventN` est inférieur à 25.

### API REST pour les services Home Assistant

L'add-on expose plusieurs commandes de service (via l'API REST) que vous pouvez utiliser dans les automatisations Home Assistant. Le service `rest_command` doit être configuré dans votre `configuration.yaml` Home Assistant.

**Attention :** Le `slug` de l'add-on est **haoslutumakiosk**.

**Exemples de configuration dans `configuration.yaml` (HA) :**
```yaml
rest_command:
  haoslutumakiosk_launch_url:
    url: http://[HAOS_IP]:8080/launch_url
    method: POST
    headers:
      Content-Type: application/json
    payload: '{"url": "{{ url }}"}'
  haoslutumakiosk_refresh_browser:
    url: http://[HAOS_IP]:8080/refresh_browser
    method: POST
  haoslutumakiosk_is_display_on:
    url: http://[HAOS_IP]:8080/is_display_on
    method: GET
  haoslutumakiosk_display_on:
    url: http://[HAOS_IP]:8080/display_on
    method: POST
    payload: '{"timeout": "{{ timeout }}"}'
  haoslutumakiosk_display_off:
    url: http://[HAOS_IP]:8080/display_off
    method: POST
  haoslutumakiosk_current_processes:
    url: http://[HAOS_IP]:8080/current_processes
    method: GET
  haoslutumakiosk_xset:
    url: http://[HAOS_IP]:8080/xset
    method: POST
    payload: '{"args": "{{ args }}"}'
  haoslutumakiosk_run_command:
    url: http://[HAOS_IP]:8080/run_command
    method: POST
    payload: '{"cmd": "{{ cmd }}"}'
