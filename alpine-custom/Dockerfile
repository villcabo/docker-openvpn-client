# FROM alpine:latest
FROM ubuntu:latest

LABEL maintainer="Bismarck Villca <bismarck.villca@gmail.com>"

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    openvpn \
    iptables \
    net-tools \
    iproute2 \
    iputils-ping \
    curl \
    dnsutils \
    procps \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Setting ssh server
# RUN sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config
# RUN sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
# RUN sed -i 's/X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config

# Create alpine user
ARG USER=root
ARG PASS=root
# ENV HOME=/home/$USER
# RUN addgroup -g 1000 $USER
# RUN adduser -u 1000 -G $USER -h $HOME -D $USER
# RUN echo -n $USER:$PASS | chpasswd

# Copy files
EXPOSE 22
COPY start-ovpn.sh /start-ovpn.sh
COPY start-sshserver.sh /start-sshserver.sh
COPY entrypoint.sh /entrypoint.sh

# Entrypoint
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]