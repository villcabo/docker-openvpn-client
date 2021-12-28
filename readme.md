# Docker OpenVPN Client

This image is based on **alpine**

Build image with default arguments:
```
docker-compose build --force-rm
```

Build image with custom arguments:
```
docker-compose build --build-arg USER=alpine --build-arg PASS=alpine --force-rm
```

Start container:
```
docker-compose up -d
```
