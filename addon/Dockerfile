ARG BUILD_FROM
FROM ${BUILD_FROM}

WORKDIR /

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        xserver-xorg xserver-xorg-legacy x11-xserver-utils \
        xdotool xclip setxkbmap unclutter openbox \
        firefox-esr onboard python3 python3-pip python3-venv \
        curl git tcl tk dbus-x11 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip
RUN pip install CherryPy

COPY run.sh /run.sh
COPY rest_server.py /rest_server.py
COPY toggle_keyboard.py /toggle_keyboard.py

RUN sed -i 's/\r$//' /run.sh && \
    sed -i 's/\r$//' /rest_server.py && \
    sed -i 's/\r$//' /toggle_keyboard.py && \
    chmod +x /run.sh /rest_server.py /toggle_keyboard.py

CMD ["/run.sh"]




