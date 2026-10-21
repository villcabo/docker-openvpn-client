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
- `SHARED_IPS` — subnets/hosts that `manage.sh` routes through the container on the host. A multi-line double-quoted value, one entry per line with optional `#` comments (see `.env.example`). `parse_shared_ips` strips comments and commas, drops duplicates and skips invalid or `/0` entries. Docker Compose also parses `.env`, so the value must stay double-quoted: compose accepts multi-line quoted values, bash `source` alone would not drop the comments.

## Architecture

The project is a thin wrapper that turns a disposable Ubuntu container into a LAN-side VPN gateway. Three pieces cooperate:

1. **`ubuntu-custom/` — the container image** (`FROM ubuntu:26.04`). Installs `openvpn`, `iptables`, `iproute2`, `procps`. `entrypoint.sh`:
   - Writes credentials to `/root/vpn.auth` (mode 0600) from env vars.
   - Installs NAT/forwarding rules (idempotent, `iptables -C` guard) so traffic entering via `eth0` is MASQUERADEd out `tun0`. They reference `tun0` by name, so they go in before the interface exists:
     - `iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE`
     - `FORWARD` rules between `eth0` and `tun0` (stateful return path).
   - `exec openvpn` in the foreground with `--keepalive 10 60 --persist-tun --server-poll-timeout 5`. OpenVPN becomes PID 1: its output is `docker logs`, it gets SIGTERM on `docker stop`, and if it exits the container exits and `restart: unless-stopped` brings it back.

2. **`docker-compose.yml` — container runtime.** Declares a dedicated bridge network `vpn-network` with subnet `10.55.11.0/28`. Grants only `NET_ADMIN` (plus `no-new-privileges`), mounts `/dev/net/tun` and the `.ovpn` read-only, sets `net.ipv4.ip_forward=1`, and uses only the internal DNS. The container is not on the host network — clients reach it via its bridge IP, which `manage.sh` looks up dynamically.

3. **`manage.sh` — host-side orchestrator.** Run with `sudo`. Key phases:
   - `start_vpn`: ensures the container is up (`docker compose up -d`), validates the OpenVPN service via `is_service_running` (checks `pgrep openvpn` + presence of a `tun*` interface inside the container — not a ping test), and if missing, runs `docker restart` (OpenVPN is PID 1, so that restarts it). Then calls `add_routes`.
   - `add_routes` / `delete_routes`: for each subnet in `SHARED_IPS`, runs `ip route add <subnet> via <container-ip> dev <local-iface>` on the host. The container IP comes from `docker inspect`; the local interface is derived from `ip route get <container-ip>`. This is what makes the host (and anything routing through it) send traffic for those subnets through the VPN container.
   - `add_forwarding` / `delete_forwarding`: insert/remove two `ACCEPT` rules in the `DOCKER-USER` iptables chain (`-i <vpn-bridge>` and `-o <vpn-bridge>`). This lets **other containers on any Docker network** reach `SHARED_IPS` through the VPN — without them, only host-originated traffic works because Docker's `DOCKER-ISOLATION` rules drop the cross-bridge forward from another network's bridge to the VPN container's bridge. `DOCKER-USER` is evaluated before isolation, so an `ACCEPT` there short-circuits it. `resolve_container_net` is the shared helper that sets `CONTAINER_IP` + `LOCAL_INTERFACE` (the `br-xxxx` device) for both routing and forwarding.
   - `stop_vpn` (`--stop`): removes host routes only. The container and VPN session stay up.
   - `down_vpn` (`--down`): removes host routes **and** runs `docker compose down` (removes the container, not just stops it).
   - `--debug` flips `DEBUG_MODE=true` which enables the `log debug` branch, currently used to trace `is_service_running`.

### Things to know before editing

- **No log sentinel.** `wait_for_vpn_startup` polls the same check as `is_service_running` (process + `tun*`); log lines can change freely.
- **Service health = process + tun interface**, not connectivity. Earlier versions used ping; the commit history shows this was intentionally removed. Don't reintroduce ping-based checks without discussing.
- **`CONTAINER_NAME` comes from `.env`** in both `manage.sh` and `docker-compose.yml`, each with the fallback `openvpn-client`. Change the fallback in both places if you rename it.
- **Host routes persist only until `--stop`.** They are not written to any network config file; a reboot clears them, and re-running `--start` re-adds them.
- **`DOCKER-USER` rules are flushed on Docker daemon restart** (not on container or host reboot of the VPN container alone — specifically `systemctl restart docker`). `--start` re-adds them idempotently (`iptables -C` guard). The rules match on the **bridge interface** (`-i/-o br-xxxx`), NOT the container IP — a forwarded packet's destination is the final `SHARED_IPS` address, not the VPN container's IP, so an IP-based match would never fire.
- **Don't re-run the entrypoint with `docker exec`.** OpenVPN is PID 1; a second instance would fight it for `tun0`. Recovery is `docker restart`.
- **A wrong password means a restart loop.** OpenVPN exits on `AUTH_FAILED`, the container restarts with Docker's backoff (capped at about one attempt a minute) and keeps hitting the Sophos server until `--down`.
