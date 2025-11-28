################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk) - MODIFIÉ POUR LUTUMBA
# File: Dockerfile
# Version: 1.1.2
# Copyright Jeff Kosowsky
# Date: September 2025
################################################################################

ARG BUILD_FROM
FROM $BUILD_FROM

# Install Lutumba and necessary dependencies
RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-modesetting \
    xf86-input-libinput \
    libinput \
#   libinput-tools \
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
#    xfce4-settings \
#    xfwm4 \
#    xfce4-session \
    onboard \
    py3-pip \
    python3-tkinter \
    patch \
    bash \
    # --- Remplacement de Luakit par Lutumba ---
    && apk add --no-cache lutumba \  
    # ----------------------------------------
    && rm -rf /var/cache/apk/*

# Set the display variable
ENV DISPLAY=:0

# Copy over 'xorg.conf.default'
COPY xorg.conf.default /etc/X11/
# La ligne 'COPY userconf.lua...' est retirée
COPY translations/*.yaml /translations/

# Install aiohttp (necessaire pour rest_server.py)
RUN pip3 install --no-cache-dir aiohttp

# Copy over python scripts, run.sh and xset.d file
COPY rest_server.py /
COPY toggle_keyboard.py /
COPY xset.d /etc/X11/xset.d/

# Les lignes pour 'unique_instance.patch' sont retirées

COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]
