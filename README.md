# TZSP-to-NTRIP Bridge

Captures RTCM3 correction data from a MikroTik router's packet sniffer (via TZSP) and re-serves it as an NTRIP v1 caster. Useful when you have a base station sending corrections through a MikroTik network and want to feed rovers without a dedicated NTRIP caster.

Single Python script, no external dependencies (stdlib only), Python 3.6+.

## Quick Start

```bash
python3 ntrip_bridge.py
```

The bridge listens on:
- **UDP 37008** — TZSP packets from the MikroTik sniffer
- **TCP 2101** — NTRIP caster for rover connections (mount point `/RTCM3`)

## MikroTik Setup

The packet sniffer captures RTCM3 traffic passing through the router and mirrors it via TZSP to the machine running this bridge.

### 1. Identify the RTCM3 traffic

Determine the IP and port of your base station's RTCM3 stream. For example, if your base station sends corrections from `192.168.1.10` on UDP port `9999`.

### 2. Configure the packet sniffer

In the MikroTik terminal:

```routeros
/tool sniffer set enabled=no
/tool sniffer set filter-port=9999 filter-ip-address=192.168.1.10/32 \
    filter-ip-protocol=udp streaming-enabled=yes \
    streaming-server=<bridge-machine-ip>:37008
/tool sniffer set enabled=yes
```

Or in Winbox:

1. Go to **Tools > Packet Sniffer**
2. On the **General** tab, check **Streaming Enabled**
3. On the **Streaming** tab, set **Server** to the IP of the machine running this bridge (port 37008)
4. On the **Filter** tab, set the filter to match your RTCM3 traffic (source IP, port, protocol)
5. Click **Apply**, then **Start**

### 3. Verify

You should see log output from the bridge when RTCM3 data starts flowing:

```
TZSP-to-NTRIP bridge starting
  TZSP receiver : UDP 37008
  NTRIP caster  : TCP 2101 (mount /RTCM3)

[tzsp] listening on UDP port 37008
[ntrip] listening on TCP port 2101
[tzsp] receiving RTCM3 data from ('192.168.1.1', 37008) (245 bytes)
```

## Rover Configuration

Point your rover's NTRIP client at:

| Field      | Value                          |
|------------|--------------------------------|
| Host       | IP of the machine running this bridge |
| Port       | `2101`                         |
| Mount point| `RTCM3`                        |
| Username   | (any or blank)                 |
| Password   | (any or blank)                 |

No authentication is required. The bridge accepts any credentials.

## How It Works

```
Base Station ──RTCM3──▶ MikroTik Router ──TZSP──▶ ntrip_bridge.py ──NTRIP──▶ Rover(s)
                         (packet sniffer)          UDP 37008 → TCP 2101
```

1. The MikroTik packet sniffer captures RTCM3 packets matching the filter and wraps them in TZSP (TaZmen Sniffer Protocol), sending them over UDP to the bridge.
2. The bridge strips the TZSP encapsulation, extracts the UDP payload from the inner Ethernet/IP frame, validates the RTCM3 preamble (`0xD3`), and broadcasts the raw bytes to all connected NTRIP clients.
3. Rovers connect via standard NTRIP v1 and receive the corrections as a continuous stream.

## Notes

- Multiple rovers can connect simultaneously.
- The bridge does not parse RTCM3 message internals — it passes through raw bytes.
- If the MikroTik sends Ethernet-framed or raw-IP captures, both are handled automatically.
- No persistent state or configuration files. Stop it with Ctrl+C.
