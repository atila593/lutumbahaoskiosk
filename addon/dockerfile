ARG BUILD_FROM
ARG BUILD_ARCH
ARG BUILD_VERSION

# CORRECTION FINALE : Utilisation de l'image de base Alpine publique
# Nous utilisons 'alpine:3.18' qui est accessible publiquement, au lieu de l'image interne de HA.
FROM alpine:3.18

# Install necessary dependencies, y compris Firefox ESR, Xorg et dépendances d'entrée
RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-modesetting \
    xf86-input-libinput \
    libinput \
    udev \
    libinput-udev \
    libevdev \
    mesa-dri-gallium \
    mesa-egl \
    mesa-gles \
    libdrm \
    libxkbcommon \
    ttf-dejavu \
    util-linux \
    xdotool \
    xinput \
    xrandr \
    xset \
    unclutter-xfixes \
    setxkbmap \
    openbox \
    onboard \
    py3-pip \
    python3-tkinter \
    patch \
    bash \
    xclip \
    firefox-esr \
    nss \
    # Ajout d'une dépendance pour garantir la compatibilité Python/pip3 avec les paquets Alpine 
    py3-cryptography \
    && rm -rf /var/cache/apk/*

# Set the display variable
ENV DISPLAY=:0

# Copy over 'xorg.conf.default' and other configuration files
COPY xorg.conf.default /etc/X11/
COPY translations/*.yaml /translations/

COPY run.sh /
RUN chmod a+x /run.sh

COPY rest_server.py /
COPY toggle_keyboard.py /

# Install python dependencies (aiohttp et cherrypy sont nécessaires pour le serveur REST)
RUN pip3 install aiohttp cherrypy

# Create log directory and change permissions for files
RUN mkdir -p /var/log/supervisor && \
    chmod a+rwx /var/log/supervisor && \
    chmod a+x /run.sh && \
    chmod a+x /rest_server.py && \
    chmod a+x /toggle_keyboard.py

# Final command
CMD ["/run.sh"]
