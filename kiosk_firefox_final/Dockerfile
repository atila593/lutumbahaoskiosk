# -----------------------------
# Base image
# -----------------------------
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM ${BUILD_FROM}

# -----------------------------
# Arguments et variables
# -----------------------------
ENV VENV_PATH=/opt/venv
ENV PATH="${VENV_PATH}/bin:$PATH"
ENV DISPLAY=:0

# -----------------------------
# Installer les dépendances système
# -----------------------------
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

# -----------------------------
# Créer un virtualenv pour Python
# -----------------------------
RUN python3 -m venv $VENV_PATH \
    && $VENV_PATH/bin/pip install --upgrade pip \
    && $VENV_PATH/bin/pip install CherryPy

# -----------------------------
# Copier les scripts
# -----------------------------
COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py

# -----------------------------
# Copier la config Xorg si besoin
# -----------------------------
# COPY xorg.conf.default /etc/X11/xorg.conf.default
# Tu peux remplacer par ta propre config si nécessaire

# -----------------------------
# Permissions
# -----------------------------
RUN chmod +x /run.sh

# -----------------------------
# Commande par défaut
# -----------------------------
CMD ["/run.sh"]


