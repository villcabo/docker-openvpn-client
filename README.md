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

### Show Help

```bash
bash manage.sh --help
```

## Global Configuration

Create a `.env` file in the root directory with the following variables:

```properties
PATH_CONF=/path/to/file.ovpn
VPN_USERNAME=username
VPN_PASSWORD=password
SHARED_IPS="192.168.1.0/24 10.0.0.0/16"
VPN_VALIDATION_IP=8.8.8.8
```

- `PATH_CONF`: Path to the OpenVPN configuration file.
- `VPN_USERNAME`: Username for OpenVPN authentication.
- `VPN_PASSWORD`: Password for OpenVPN authentication.
- `SHARED_IPS`: Space-separated list of subnets to route through the VPN container.
- `VPN_VALIDATION_IP`: IP address to ping for VPN connectivity validation (default: 199.3.0.108).

## How It Works

- The script will start the container if it is not running.
- It will ensure the OpenVPN service is running and connected.
- It will configure the specified routes (`SHARED_IPS`) to go through the VPN container.
- On stop, it will remove the routes and stop the container.

## Notes

- You must run the script with `sudo` to allow route changes on the host.
- All logs are color-coded and sectioned for clarity.
- The script is self-contained; you do not need to run any other setup scripts.
