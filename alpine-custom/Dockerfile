FROM alpine:3.15.0

LABEL maintainer="Bismarck Villca bismarck.villca@gmail.com"

# Install dependencies
RUN apk add --update --no-cache openssh openvpn vim

# Setting ssh server
RUN sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config
RUN sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
RUN sed -i 's/X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config

# Setting git
RUN git config --global user.name "Bismarck Villca Soliz" && git config --global user.email "bismarckv@sintesis.com.bo"

# Create alpine user
ARG USER=alpine
ARG PASS=alpine
ENV HOME=/home/$USER
RUN addgroup -g 1000 $USER
RUN adduser -u 1000 -G $USER -h $HOME -D $USER
RUN echo -n $USER:$PASS | chpasswd

# Copy files
EXPOSE 22
COPY start-ovpn.sh /start-ovpn.sh
COPY start-sshserver.sh /start-sshserver.sh
COPY entrypoint.sh /entrypoint.sh

# Entrypoint
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]