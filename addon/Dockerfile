ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:latest
FROM $BUILD_FROM

# Définir le répertoire de travail
WORKDIR /

# ----------------------------------------------------------------------
# Dépendances système
# ----------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        xserver-xorg \
        xserver-xorg-legacy \
        x11-xserver-utils \
        xdotool \
        xclip \
        setxkbmap \
        unclutter \
        openbox \
        firefox-esr \
        onboard \
        python3 \
        python3-pip \
        python3-cherrypy3 \
        curl \
        git \
        tcl \
        tk \
        dbus-x11 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

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



