# Docker OpenVPN Client

This image is based on **alpine**

Build image with default arguments:
```
docker-compose build --force-rm
```

Build image with custom arguments:
```
docker-compose build --force-rm --build-arg USER=alpine --build-arg PASS=alpine
```

Start container:
```
docker-compose up -d
```

Start container with build:
```
docker-compose up -d --build
```

## Connect vnc via ssh
First, a ssh tunnel must be mounted locallyhost:
```
ssh -L 5901:localhost:5901 USER@REMOTE_IP
```
Second, you need to connect, using **vncviewer** to **localhost:5901**


## Global Config
Create file .env in root directory

Environment available:
```
PATH_CONF=/path/to/file.ovpn
OVPN_USERNAME=username
OVPN_PASSWORD=password
```