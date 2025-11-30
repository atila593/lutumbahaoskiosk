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
            unclutter \
            openbox \
            firefox \
            onboard \
            python3 \
            py3-pip \
            curl \
            git \
            tcl \
            tk \
            jq \
            dbus \
            && \
        rm -rf /var/cache/apk/*; \
    fi

# ------------------------------------------------------------------------------
# Environnement Virtuel Python (VENV)
# ------------------------------------------------------------------------------
# Ces étapes s'exécutent après l'installation des dépendances python3 et pip/py3-pip
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Installation des dépendances Python (CherryPy) dans le VENV
RUN pip install --upgrade pip && \
    pip install CherryPy

# ------------------------------------------------------------------------------
# Copie des fichiers et Permissions
# J'ai mis à jour les chemins pour correspondre à vos COPY précédents
# ------------------------------------------------------------------------------
COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py
COPY xorg.conf.default /etc/X11/xorg.conf.default

RUN sed -i 's/\r$//' /run.sh && \
    sed -i 's/\r$//' /rest_server.py && \
    sed -i 's/\r$//' /toggle_keyboard.py && \
    chmod +x /run.sh /rest_server.py /toggle_keyboard.py 

# IMPORTANT : Ajout de la permission pour le fichier de configuration Xorg
RUN chmod 644 /etc/X11/xorg.conf.default


# ------------------------------------------------------------------------------
# Exécution
# ------------------------------------------------------------------------------
CMD ["/run.sh"]


