ARG BUILD_FROM
FROM ${BUILD_FROM}

WORKDIR /

# ------------------------------------------------------------------------------
# Dépendances système (APT vs APK)
# Script conditionnel pour gérer le problème de cache Alpine/Debian persistant.
# ------------------------------------------------------------------------------
RUN \
    if command -v apt-get >/dev/null; then \
        # Installation pour base Debian (apt-get)
        echo "Using apt-get (Debian base)"; \
        apt-get update && \
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
            python3-venv \
            curl \
            git \
            tcl \
            tk \
            jq \
            dbus-x11 \
            libinput-tools \
            udev \
            && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        # Installation pour base Alpine (apk)
        echo "Using apk (Alpine base)"; \
        apk update && \
        apk add --no-cache \
            xorg-server \
            xrandr \
            xdotool \
            xclip \
            setxkbmap \
            unclutter-xfixes \
            openbox \
            firefox \
            onboard \
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
            && \
        rm -rf /var/cache/apk/*; \
    fi

# ------------------------------------------------------------------------------
# Environnement Virtuel Python (VENV)
# ------------------------------------------------------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Installation des dépendances Python (CherryPy) dans le VENV
RUN pip install --upgrade pip && \
    pip install CherryPy

# ------------------------------------------------------------------------------
# Copie des fichiers et Permissions
# ------------------------------------------------------------------------------
COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py
COPY xorg.conf.default /etc/X11/xorg.conf.default

# Nettoyage des fins de ligne Windows et attribution des permissions
RUN sed -i 's/\r$//' /run.sh && \
    sed -i 's/\r$//' /rest_server.py && \
    sed -i 's/\r$//' /toggle_keyboard.py && \
    chmod a+x /run.sh && \
    chmod 644 /etc/X11/xorg.conf.default

# ------------------------------------------------------------------------------
# Exécution - IMPORTANT: Utiliser la forme shell, pas exec form
# ------------------------------------------------------------------------------
RUN mkdir -p /etc/services.d/kiosk && \
    mv /run.sh /etc/services.d/kiosk/run && \
    chmod +x /etc/services.d/kiosk/run
