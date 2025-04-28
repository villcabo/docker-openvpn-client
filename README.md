# Docker OpenVPN Client

This image is based on **ubuntu:latest**.

## Build the Image

### Build with Default Arguments
```bash
docker compose build --no-cache
```

## Start the Container

```bash
docker compose up -d
```

## Global Configuration

### Create a `.env` File
Create a `.env` file in the root directory with the following variables:

```properties
PATH_CONF=/path/to/file.ovpn
VPN_USERNAME=username
VPN_PASSWORD=password
SHARED_IPS="192.168.1.0/24 10.0.0.0/16"
```

### Environment Variables

#### `PATH_CONF`
- **Description**: Path to the OpenVPN configuration file.
- **Example**: `/etc/openvpn/client.ovpn`

#### `VPN_USERNAME`
- **Description**: Username for OpenVPN authentication.
- **Example**: `myusername`

#### `VPN_PASSWORD`
- **Description**: Password for OpenVPN authentication.
- **Example**: `mypassword`

#### `SHARED_IPS`
- **Description**: Space-separated list of subnets to route through the VPN container.
- **Example**: `"192.168.1.0/24 10.0.0.0/16"`

## Shared IP Configuration

### Configure Shared IPs
```bash
bash configure_shared_ips.sh
```

The `SHARED_IPS` variable is used to define subnets that should be routed through the VPN container. These routes are automatically configured when the container starts.

### Example
If `SHARED_IPS="192.168.1.0/24 10.0.0.0/16"`, the following routes will be added:
- `192.168.1.0/24` via the VPN container
- `10.0.0.0/16` via the VPN container

### Verify Routes
To verify that the routes have been added, you can use the following command:
```
ip route show | grep -E "192.168.1.0/24|10.0.0.0/16"
```

## Notes
- Ensure that the container has the necessary permissions to modify routes on the host machine.
- Use `sudo` if required when running the script to configure shared IPs.
