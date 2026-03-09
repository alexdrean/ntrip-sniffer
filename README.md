# TZSP-to-NTRIP Bridge

Captures RTCM3 correction data from a MikroTik router's packet sniffer (via TZSP) and re-serves it as an NTRIP v1 caster. Useful when you have a base station sending corrections through a MikroTik network and want to feed rovers without a dedicated NTRIP caster.

Written in Go. Compiles to a single static binary with no runtime dependencies.

## Quick Start

```bash
go build -o ntrip_bridge .
./ntrip_bridge
```

The bridge listens on:
- **UDP 37008** — TZSP packets from the MikroTik
- **TCP 2101** — NTRIP caster for rover connections

## MikroTik Setup

The packet sniffer captures RTCM3 traffic passing through the router and mirrors it via TZSP to the machine running this bridge.

```routeros
/ip firewall mangle
add chain=prerouting \
    src-address=<base-station-ip> \
    connection-state=new \
    action=mark-connection \
    new-connection-mark=rtcm3
add chain=prerouting \
    connection-mark=rtcm3 \
    action=sniff-tzsp \
    sniff-target=<bridge-machine-ip> \
    sniff-target-port=37008
```

The first rule marks new connections from the base station. The second rule mirrors packets belonging to marked connections via TZSP, avoiding per-packet address matching.

### Verify

You should see log output when RTCM3 data starts flowing:

```
TZSP-to-NTRIP bridge starting
  TZSP receiver : UDP 37008
  NTRIP caster  : TCP 2101
  Mountpoints   : dynamic (from TZSP source IPs)

[tzsp] listening on UDP port 37008
[ntrip] listening on TCP port 2101
[tzsp] RTCM3 source 192.168.1.1 (via 10.0.0.1:37008, 245 bytes) -> /192.168.1.1
```

## Authentication

Copy `users.conf.example` to `users.conf` to enable HTTP Basic authentication. Format: `username:password`, one per line. If `users.conf` is absent, all connections are accepted.

## Rover Configuration

Point your rover's NTRIP client at:

| Field       | Value                                 |
|-------------|---------------------------------------|
| Host        | IP of the machine running this bridge |
| Port        | `2101`                                |
| Mount point | (from sourcetable, e.g. `192.168.1.1`)|

## How It Works

```
Base Station ──RTCM3──> MikroTik Router ──TZSP──> ntrip_bridge ──NTRIP──> Rover(s)
                          (packet sniffer)        UDP 37008 -> TCP 2101
```

1. MikroTik captures RTCM3 packets matching the filter and wraps them in TZSP (TaZmen Sniffer Protocol), sending them over UDP to the bridge.
2. The bridge strips the TZSP encapsulation, extracts the transport payload from the inner IP frame, validates each RTCM3 frame (preamble, reserved bits, CRC-24Q), and broadcasts to all connected NTRIP clients.
3. Rovers connect via standard NTRIP v1 and receive corrections as a continuous stream.

## Deployment

The built binary is statically linked and portable — copy it to any Linux machine (including Raspberry Pi with `GOARCH=arm`).

### Cross-compile for Raspberry Pi

```bash
GOOS=linux GOARCH=arm GOARM=7 go build -o ntrip_bridge .
```

### Run with pm2

```bash
pm2 start ./ntrip_bridge --name ntrip-bridge
pm2 save && pm2 startup
```

View logs: `pm2 logs ntrip-bridge`

### Run with systemd

Create `/etc/systemd/system/ntrip-bridge.service`:

```ini
[Unit]
Description=TZSP-to-NTRIP Bridge
After=network.target

[Service]
ExecStart=/opt/ntrip_bridge/ntrip_bridge
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now ntrip-bridge
```

## Building from Source

Requires Go 1.21+:

```bash
go build -o ntrip_bridge .
```

## Notes

- Multiple rovers can connect simultaneously.
- Mountpoints are created dynamically from RTCM3 source IPs.
- The bridge validates RTCM3 frames (preamble, reserved bits, CRC-24Q) but does not parse message internals.
- Both Ethernet-framed and raw-IP TZSP captures are handled automatically.
- Both UDP and TCP inner payloads are supported.
