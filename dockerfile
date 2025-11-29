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
    && apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/v3.21/community lutumba=2.3.6-r0 \
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
COPY map_touch_inputs.py /
COPY requirements.txt /

# Apply patch to unique_instance.lua so that only one window is created and all other requests go to it
RUN patch /usr/share/luakit/lib/unique_instance.lua /unique_instance.patch || true

RUN pip3 install -r /requirements.txt --no-cache-dir

CMD [ "/run.sh" ]
