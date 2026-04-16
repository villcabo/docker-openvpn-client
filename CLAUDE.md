# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Build the image (from repo root, reads `docker-compose.yml`):

```bash
docker compose build --no-cache
```

Manage the VPN (all operations go through `manage.sh`, which must run as root because it manipulates host routing):

```bash
sudo bash manage.sh --start   # or -s : start container, verify OpenVPN, add host routes
sudo bash manage.sh --stop    # or -k : remove host routes only (container stays running)
sudo bash manage.sh --down    # remove host routes AND stop/remove the container
sudo bash manage.sh --debug   # run service validation with verbose debug logging
bash manage.sh --help         # or -h
```

There is no test suite, linter, or build step beyond the Docker image build.

## Configuration

Runtime configuration lives in `.env` (copy from `.env.example`). `manage.sh` sources it directly, and `docker-compose.yml` consumes a subset via variable substitution.

Required variables:
- `PATH_CONF` — absolute host path to the `.ovpn` file; mounted into the container as `/root/vpn.ovpn`.
- `VPN_USERNAME` / `VPN_PASSWORD` — passed to the container as `OVPN_USERNAME` / `OVPN_PASSWORD` and written to `/root/vpn.auth` by the entrypoint.
- `CONTAINER_NAME` — must match `container_name` in `docker-compose.yml` (currently hardcoded to `openvpn-client` in both places; keep them in sync if renamed).
- `SHARED_IPS` — space-separated list of subnets (e.g. `"192.168.1.0/24 10.0.0.0/16"`) that `manage.sh` routes through the container on the host.

## Architecture

The project is a thin wrapper that turns a disposable Ubuntu container into a LAN-side VPN gateway. Three pieces cooperate:

1. **`ubuntu-custom/` — the container image** (`FROM ubuntu:24.04`). Installs `openvpn`, `iptables`, `iproute2`, etc. `entrypoint.sh` runs as PID 1 and:
   - Writes credentials to `/root/vpn.auth` from env vars.
   - Launches `openvpn --daemon` against `/root/vpn.ovpn`.
   - Waits up to 30s for `tun0` to appear.
   - Installs NAT/forwarding rules so traffic entering via `eth0` is MASQUERADEd out `tun0`:
     - `iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE`
     - `FORWARD` rules between `eth0` and `tun0` (stateful return path).
   - `tail -f /dev/null` to keep the container alive. The final log line `VPN connected and configured. Keeping the container active.` is the sentinel `manage.sh` greps for to detect successful startup.

2. **`docker-compose.yml` — container runtime.** Declares a dedicated bridge network `vpn-network` with subnet `10.55.11.0/28`. Grants `NET_ADMIN` + `SYS_ADMIN`, mounts `/dev/net/tun`, sets `net.ipv4.ip_forward=1`, and fixes DNS. The container is not on the host network — clients reach it via its bridge IP, which `manage.sh` looks up dynamically.

3. **`manage.sh` — host-side orchestrator.** Run with `sudo`. Key phases:
   - `start_vpn`: ensures the container is up (`docker compose up -d`), validates the OpenVPN service via `is_service_running` (checks `pgrep openvpn` + presence of a `tun*` interface inside the container — not a ping test), and if missing, re-runs `/entrypoint.sh` via `docker exec`. Then calls `add_routes`.
   - `add_routes` / `delete_routes`: for each subnet in `SHARED_IPS`, runs `ip route add <subnet> via <container-ip> dev <local-iface>` on the host. The container IP comes from `docker inspect`; the local interface is derived from `ip route get <container-ip>`. This is what makes the host (and anything routing through it) send traffic for those subnets through the VPN container.
   - `stop_vpn` (`--stop`): removes host routes only. The container and VPN session stay up.
   - `down_vpn` (`--down`): removes host routes **and** runs `docker compose down` (removes the container, not just stops it).
   - `--debug` flips `DEBUG_MODE=true` which enables the `log debug` branch, currently used to trace `is_service_running`.

### Things to know before editing

- **Startup sentinel is a string match.** `wait_for_vpn_startup` greps `docker logs --tail 1` for the exact string `VPN connected and configured. Keeping the container active.` If you change that line in `ubuntu-custom/entrypoint.sh`, update `VPN_STARTUP_MESSAGE` in `manage.sh` to match.
- **Service health = process + tun interface**, not connectivity. Earlier versions used ping; the commit history shows this was intentionally removed. Don't reintroduce ping-based checks without discussing.
- **`CONTAINER_NAME` is duplicated.** It is hardcoded in `manage.sh` (`CONTAINER_NAME="openvpn-client"`) *and* in `docker-compose.yml` (`container_name: openvpn-client`). `.env` also documents it. Any rename must touch all three.
- **Host routes persist only until `--stop`.** They are not written to any network config file; a reboot clears them, and re-running `--start` re-adds them.
- **Entrypoint can be re-run inside a live container.** `manage.sh` does `docker exec -d "$CONTAINER_NAME" bash /entrypoint.sh` as a recovery path — `entrypoint.sh` starts with `pkill openvpn` specifically to support this.
