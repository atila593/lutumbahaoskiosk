# Fichier: toggle_keyboard.py pour l'add-on Lutumba Kiosk Display
# Crée un pixel cliquable (1x1) dans le coin supérieur droit pour afficher/masquer
# le clavier virtuel Onboard via DBus.

import tkinter as tk
import subprocess
import sys

def toggle_keyboard(event):
    """Envoie une commande D-Bus pour basculer la visibilité du clavier Onboard."""
    subprocess.Popen([
        "dbus-send",
        "--type=method_call",
        "--print-reply",
        "--dest=org.onboard.Onboard",
        "/org/onboard/Onboard/Keyboard",
        "org.onboard.Onboard.Keyboard.ToggleVisible"
    ])

# Crée la fenêtre principale tkinter (un pixel)
root = tk.Tk()
# Retire les bordures de la fenêtre (la rend invisible en tant que fenêtre)
root.overrideredirect(True)
# Positionne le pixel à la coordonnée (écran_largeur - 1, 0)
root.geometry("+{}+{}".format(root.winfo_screenwidth()-1, 0))
# Assure que la fenêtre reste au-dessus des autres
root.attributes("-topmost", True)

# Détermine la couleur du pixel (passée en argument depuis run.sh)
color = "black" if len(sys.argv) > 1 and sys.argv[1].lower() == "true" else "white"

# Crée le "bouton" (Canvas 1x1)
canvas = tk.Canvas(root, width=1, height=1, highlightthickness=0, bg=color)
canvas.pack()

# Lie le clic de la souris à la fonction de basculement du clavier
canvas.bind("<Button-1>", toggle_keyboard)

# Lance la boucle principale de l'interface graphique
root.mainloop()
