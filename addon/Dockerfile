# Dockerfile

# Image de base Debian pour HAOS (HAOS gère le choix d'architecture via config.yaml)
FROM ghcr.io/home-assistant/amd64-base-debian:latest

# Définir le répertoire de travail
WORKDIR /

# ----------------------------------------------------------------------
# Dépendances système
# ----------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        xserver-xorg \
        xserver-xorg-legacy \
        xorg \
        xrandr \
        xdotool \
        xclip \
        setxkbmap \
        unclutter \
        openbox \
        firefox-esr \
        onboard \
        python3 \
        python3-pip \
        curl \
        git \
        tcl \
        tk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Dépendances Python
RUN pip3 install CherryPy

# ----------------------------------------------------------------------
# Copie des fichiers
# ----------------------------------------------------------------------
COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py

# ----------------------------------------------------------------------
# Fix permissions + suppression CRLF
# ----------------------------------------------------------------------
RUN sed -i 's/\r$//' /run.sh && \
    sed -i 's/\r$//' /rest_server.py && \
    sed -i 's/\r$//' /toggle_keyboard.py && \
    chmod +x /run.sh && chmod +x /rest_server.py && chmod +x /toggle_keyboard.py

# ----------------------------------------------------------------------
# Exécution
# ----------------------------------------------------------------------
CMD ["/run.sh"]

