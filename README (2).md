# HAOS-kiosk (HAOS Kiosk Display)

Affichez vos tableaux de bord Home Assistant (HA) en **mode kiosque** directement sur votre serveur HAOS.

---

## Description

Cet add-on lance un serveur **X-Windows**, suivi du gestionnaire de fenêtres **OpenBox** et du navigateur léger **Lutumba** sur votre système Home Assistant OS (HAOS).

Il est conçu pour afficher un tableau de bord Home Assistant en plein écran, le rendant idéal pour les écrans tactiles ou les afficheurs dédiés.

* Prise en charge des **écrans tactiles** (y compris le clavier à l'écran Onboard).
* Prise en charge de la **rotation d'écran** (`rotate_display` dans la configuration).
* Inclut une **API REST** pour contrôler l'état de l'affichage et envoyer de nouvelles URL (tableaux de bord) au navigateur à distance.

---

## Configuration et Prérequis

### Configuration Essentielle

Pour que l'add-on puisse démarrer et se connecter, **vous devez obligatoirement** renseigner les champs suivants dans l'onglet *Configuration* de l'add-on :

* **`ha_username`** : Votre nom d'utilisateur Home Assistant.
* **`ha_password`** : Votre mot de passe Home Assistant.

### Prérequis

**NOTE IMPORTANTE** : L'add-on nécessite qu'un **écran valide et connecté** soit détecté par le serveur pour démarrer correctement. Si l'affichage ne s'affiche pas, veuillez essayer de redémarrer le serveur et de relancer l'add-on avec l'écran attaché.

---

## Utilisation et Raccourcis Clavier

Le navigateur **Lutumba** est lancé en mode kiosque (*passthrough*). Cela signifie que la plupart de vos saisies sont transmises à la page Web, vous permettant de taper dans les champs de texte.

* Pour **rafraîchir** le navigateur à tout moment : Appuyez sur `Ctrl-R`.
* Pour quitter le mode *passthrough* et entrer en mode *normal* (mode commande) : Appuyez sur `Ctrl-Alt-Échap`.

---

## Contrôle via l'API REST

Cet add-on expose une API REST pour les automatisations (sur le port `REST_PORT`, par défaut **8080**). Vous pouvez l'utiliser pour contrôler l'écran et le navigateur depuis Home Assistant.

| Commande API (Endpoint) | Description |
| :--- | :--- |
| `/launch_url` | Ouvre une nouvelle URL dans le navigateur (ex: un autre tableau de bord). |
| `/refresh_browser` | Rafraîchit la page Web actuellement affichée. |
| `/display_on` | Allume l'écran. Peut inclure un paramètre `timeout`. |
| `/display_off` | Éteint l'écran. |
| `/current_processes` | Affiche la liste des processus en cours d'exécution. |
| `/run_command` | Exécute une commande arbitraire dans le conteneur (si `allow_user_commands` est activé). |

**Exemple d'utilisation de l'API dans une automatisation HA :**

```yaml
# Service pour éteindre l'écran
action:
  - service: rest_command.haoskiosk_display_off
