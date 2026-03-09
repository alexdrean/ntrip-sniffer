# TZSP-to-NTRIP Bridge

Captures RTCM3 correction data from a MikroTik router's packet sniffer (via TZSP) and re-serves it as an NTRIP v1 caster. Useful when you have a base station sending corrections through a MikroTik network and want to feed rovers without a dedicated NTRIP caster.

Written in Erlang/OTP. Binary pattern matching handles protocol parsing cleanly, and OTP supervision provides self-healing reliability for unattended deployment.

## Quick Start

```bash
make
./ntrip_bridge
```

The bridge listens on:
- **UDP 37008** — TZSP packets from the MikroTik
- **TCP 2101** — NTRIP caster for rover connections (mount point `/RTCM3`)

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
  NTRIP caster  : TCP 2101 (mount /RTCM3)

[tzsp] listening on UDP port 37008
[ntrip] listening on TCP port 2101
[tzsp] receiving RTCM3 data from 192.168.1.1:37008 (245 bytes)
```

## Rover Configuration

Point your rover's NTRIP client at:

| Field       | Value                                 |
|-------------|---------------------------------------|
| Host        | IP of the machine running this bridge |
| Port        | `2101`                                |
| Mount point | `RTCM3`                               |
| Username    | (any or blank)                        |
| Password    | (any or blank)                        |

No authentication is required. The bridge accepts any credentials.

## How It Works

```
Base Station ──RTCM3──> MikroTik Router ──TZSP──> ntrip_bridge ──NTRIP──> Rover(s)
                          (packet sniffer)        UDP 37008 -> TCP 2101
```

1. MikroTik captures RTCM3 packets matching the filter and wraps them in TZSP (TaZmen Sniffer Protocol), sending them over UDP to the bridge.
2. The bridge strips the TZSP encapsulation, extracts the transport payload from the inner IP frame, validates each RTCM3 frame (preamble, reserved bits, CRC-24Q), and broadcasts to all connected NTRIP clients.
3. Rovers connect via standard NTRIP v1 and receive corrections as a continuous stream.

## Deployment on Raspberry Pi

The built escript is portable — copy it to the Pi.

### Install Erlang

```bash
sudo apt-get install erlang-base
```

### Run with pm2 (recommended)

```bash
pm2 start ./ntrip_bridge --name ntrip-bridge --interpreter escript
pm2 save && pm2 startup
```

View logs: `pm2 logs ntrip-bridge`

### Run with systemd (alternative)

Create `/etc/systemd/system/ntrip-bridge.service`:

```ini
[Unit]
Description=TZSP-to-NTRIP Bridge
After=network.target

[Service]
ExecStart=/usr/bin/escript /opt/ntrip_bridge/ntrip_bridge
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now ntrip-bridge
```

## Building from Source

Requires Erlang (`erlang-base` package):

```bash
make
# Output: ./ntrip_bridge (portable escript)
```

## Notes

- Multiple rovers can connect simultaneously.
- The bridge validates RTCM3 frames (preamble, reserved bits, CRC-24Q) but does not parse message internals.
- Both Ethernet-framed and raw-IP TZSP captures are handled automatically.
- Both UDP and TCP inner payloads are supported.
- No authentication, no configuration files. Stop with Ctrl+C.
