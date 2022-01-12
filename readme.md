# Docker OpenVPN Client

This image is based on **alpine**

Build image with default arguments:
```
docker-compose build --force-rm
```

Build image with custom arguments:
```
docker-compose build --force-rm --build-arg USER=alpine --build-arg PASS=adminvs
```

Start container:
```
docker-compose up -d
```

Start container with build:
```
docker-compose up -d --build
```

## Global Config
Create file .env in root directory

Environment available:
```
PATH_CONF=/path/to/file.ovpn
USERNAME=username
PASSWORD=password
```