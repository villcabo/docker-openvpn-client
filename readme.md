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
