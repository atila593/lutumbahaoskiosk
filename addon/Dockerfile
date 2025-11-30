# ----------------------------------------------------------------------
# Image de base selon l'architecture
# ----------------------------------------------------------------------
ARG BUILD_FROM
FROM $BUILD_FROM

# Définir le répertoire de travail
WORKDIR /

# ----------------------------------------------------------------------
# Dépendances système (Xorg, Firefox, utilitaires)
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
        python3-venv \
        curl \
        git \
        tcl \
        tk \
        dbus-x11 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------------------------
# Dépendances Python dans un environnement virtuel pour éviter PEP 668
# ----------------------------------------------------------------------
RUN python3 -m venv /venv && \
    /venv/bin/pip install --upgrade pip && \
    /venv/bin/pip install CherryPy

# ----------------------------------------------------------------------
# Copier les fichiers de l'addon
# ----------------------------------------------------------------------
COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py

# ----------------------------------------------------------------------
# Correction CRLF + permissions
# ----------------------------------------------------------------------
RUN sed -i 's/\r$//' /run.sh /rest_server.py /toggle_keyboard.py && \
    chmod +x /run.sh /rest_server.py /toggle_keyboard.py

# ----------------------------------------------------------------------
# Utiliser le virtualenv pour exécuter le serveur Python
# ----------------------------------------------------------------------
ENV PATH="/venv/bin:$PATH"

# ----------------------------------------------------------------------
# Point d'entrée
# ----------------------------------------------------------------------
CMD ["/run.sh"]




