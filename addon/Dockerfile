FROM ghcr.io/home-assistant/debian-addon-base:latest

# Arguments pour les architectures (ajustez si besoin)
ARG BUILD_ARCH

# Définir le répertoire de travail
WORKDIR /

# ------------------------------------------------------------------------------
# Dépendances (X-Windows, Navigateur, Utilitaires)
# ------------------------------------------------------------------------------
RUN \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        # X-Windows et utilitaires d'affichage
        xserver-xorg \
        xserver-xorg-legacy \
        xorg \
        xrandr \
        xdotool \
        xclip \
        setxkbmap \
        unclutter \
        openbox \
        # Navigateur
        firefox-esr \
        # Clavier virtuel
        onboard \
        # Python et dépendances
        python3 \
        python3-pip \
        # Autres utilitaires
        curl \
        git \
        tcl \
        tk \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Installation des dépendances Python (CherryPy pour le serveur REST)
RUN pip3 install CherryPy

# ------------------------------------------------------------------------------
# Copie des fichiers et permissions
# ------------------------------------------------------------------------------

# Copie des scripts Python et Bash (CRUCIAL pour résoudre "no such file or directory")
# Le script run.sh doit être dans le dossier de l'addon.
COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py

# Rendre les scripts exécutables
RUN chmod a+x /run.sh

# Définir le point d'entrée pour l'exécution du script principal
# Cela résout l'erreur "exec /run.sh: no such file or directory"
CMD ["/run.sh"]
