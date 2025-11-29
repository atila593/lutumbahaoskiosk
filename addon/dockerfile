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
    # NOTE: REMPLACER LA LIGNE SUIVANTE PAR LE BON PAQUET LUTUMBA
    && apk add --no-cache lutumba \
    && rm -rf /var/cache/apk/*

# Set the display variable
ENV DISPLAY=:0

# Copy over 'xorg.conf.default' and lua 'userconf.lua' file
COPY xorg.conf.default /etc/X11/
COPY userconf.lua /root/.config/lutumba/
COPY translations/*.yaml /translations/

COPY run.sh /
RUN chmod a+x /run.sh

COPY rest_server.py /
COPY toggle_keyboard.py /

# Install python dependencies
RUN pip3 install aiohttp

# Create log directory and change permissions for files
RUN mkdir /var/log/supervisor && \
    chmod a+rwx /var/log/supervisor && \
    chmod a+rwx /run.sh && \
    chmod a+rwx /rest_server.py && \
    chmod a+rwx /toggle_keyboard.py

# Final command
CMD ["/run.sh"]
