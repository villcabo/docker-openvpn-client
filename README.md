# Docker OpenVPN Client

This image is based on **ubuntu:latest**.

## Build the Image

```bash
docker compose build --no-cache
```

## Start/Stop and Manage the VPN Container

All management is now done with the `manage.sh` script:

### Start VPN and Configure Routes

```bash
sudo bash manage.sh --start
```
or
```bash
sudo bash manage.sh -s
```

### Stop VPN and Remove Routes

```bash
sudo bash manage.sh --stop
```
or
```bash
sudo bash manage.sh -k
```

### Debug Service Validation

```bash
sudo bash manage.sh --debug
```

### Show Help

```bash
bash manage.sh --help
```


## Environment Configuration

### How to configure your environment

1. Copy the example file:
	```bash
	cp .env.example .env
	```
2. Edit the `.env` file and set all variables according to your environment.

### Variables in `.env`

| Variable            | Description                                                                 | Example                          |
|---------------------|-----------------------------------------------------------------------------|----------------------------------|
| PATH_CONF           | Path to your OpenVPN configuration file (.ovpn). Must be accessible.         | /home/user/vpn/myvpn.ovpn        |
| VPN_USERNAME        | Username for OpenVPN authentication.                                         | myusername                       |
| VPN_PASSWORD        | Password for OpenVPN authentication.                                         | mypassword                       |
| CONTAINER_NAME      | Name of the Docker container for the VPN client. Must match docker-compose.   | openvpn-client                   |
| SHARED_IPS          | Space-separated list of subnets to route through the VPN container.           | "192.168.1.0/24 10.0.0.0/16"    |

#### Example `.env` file

```dotenv
PATH_CONF=/home/user/vpn/myvpn.ovpn
VPN_USERNAME=myusername
VPN_PASSWORD=mypassword
CONTAINER_NAME=openvpn-client
SHARED_IPS="192.168.1.0/24 10.0.0.0/16"
```

> **Note:**
> - All variables are required for correct operation.
> - The container name must match the name in your `docker-compose.yml`.
> - The OpenVPN config file must exist and be accessible from the container.
> - The service validation now uses VPN interface detection instead of ping tests.

## How It Works

- The script will start the container if it is not running.
- It will ensure the OpenVPN service is running and connected.
- It will configure the specified routes (`SHARED_IPS`) to go through the VPN container.
- On stop, it will remove the routes and stop the container.

## Notes

- You must run the script with `sudo` to allow route changes on the host.
- All logs are color-coded and sectioned for clarity.
- The script is self-contained; you do not need to run any other setup scripts.
