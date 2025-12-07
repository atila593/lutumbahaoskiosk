ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM ${BUILD_FROM}

# Installer Xorg, drivers Intel et Firefox
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
    eudev && \
    rm -rf /var/cache/apk/*

# Environnement Python
RUN python3 -m venv /opt/venv
RUN pip install --upgrade pip && pip install CherryPy

# Copier scripts
COPY run.sh /run.sh
COPY toggle_keyboard.py /toggle_keyboard.py
COPY rest_server.py /rest_server.py

# Permissions d'exécution
RUN chmod +x /run.sh

CMD [ "/run.sh" ]

