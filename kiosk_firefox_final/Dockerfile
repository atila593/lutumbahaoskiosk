##############################
# Dockerfile pour HAOS Kiosk
##############################

# Base image
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM ${BUILD_FROM}

# Variables d'environnement
ENV LANG=C.UTF-8
ENV DISPLAY=:0
ENV VENV_PATH=/opt/venv

# Installer paquets nécessaires
RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-intel \
    xf86-video-fbdev \
    xf86-video-vesa \
    xrandr \
    xdotool \
    xclip \
    setxkbmap \
    unclutter-xfixes \
    openbox \
    firefox \
    python3 \
    py3-pip \
    python3-tkinter \
    curl \
    git \
    tcl \
    tk \
    jq \
    dbus \
    libinput \
    eudev \
    && rm -rf /var/cache/apk/*

# Créer et utiliser le virtualenv pour CherryPy
RUN python3 -m venv $VENV_PATH \
    && $VENV_PATH/bin/pip install --upgrade pip \
    && $VENV_PATH/bin/pip install CherryPy

# Copier scripts et fichiers de config
COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py
# Si tu as un xorg.conf spécifique
# COPY xorg.conf.default /etc/X11/xorg.conf.default

# Donner les permissions d'exécution
RUN chmod +x /run.sh

# Commande par défaut
CMD [ "/run.sh" ]
