#!/usr/bin/env python3
"""TZSP-to-NTRIP bridge: receives TZSP-encapsulated RTCM3 from a MikroTik
packet sniffer and re-serves it as an NTRIP v1 caster."""

import socket
import struct
import threading
import time

TZSP_PORT = 37008
NTRIP_PORT = 2101
MOUNT_POINT = "RTCM3"

# CRC-24Q lookup table (used by RTCM3)
_crc24q_table = None


def _build_crc24q_table():
    table = []
    for i in range(256):
        crc = i << 16
        for _ in range(8):
            crc <<= 1
            if crc & 0x1000000:
                crc ^= 0x1864CFB
        table.append(crc & 0xFFFFFF)
    return table


def crc24q(data):
    """Compute CRC-24Q over bytes."""
    global _crc24q_table
    if _crc24q_table is None:
        _crc24q_table = _build_crc24q_table()
    crc = 0
    for b in data:
        crc = (_crc24q_table[(crc >> 16) ^ b] ^ (crc << 8)) & 0xFFFFFF
    return crc


def extract_rtcm3_frames(payload):
    """Extract validated RTCM3 frames from a payload.

    Returns the concatenated bytes of all frames that pass CRC-24Q validation.
    Scans for 0xD3 preamble, checks reserved bits, length, and CRC.
    """
    result = bytearray()
    pos = 0
    while pos < len(payload):
        # Scan for preamble
        if payload[pos] != 0xD3:
            pos += 1
            continue
        # Need at least 3 header bytes + 3 CRC bytes
        if pos + 6 > len(payload):
            break
        # 6 reserved bits must be 0, then 10-bit length
        length = ((payload[pos + 1] & 0x03) << 8) | payload[pos + 2]
        if payload[pos + 1] & 0xFC:
            # Reserved bits not zero — not a valid frame
            pos += 1
            continue
        frame_len = 3 + length + 3  # header + body + CRC
        if pos + frame_len > len(payload):
            break
        frame = payload[pos:pos + frame_len]
        # Validate CRC-24Q over header + body (everything except last 3 bytes)
        expected_crc = (frame[-3] << 16) | (frame[-2] << 8) | frame[-1]
        if crc24q(frame[:-3]) == expected_crc:
            result.extend(frame)
        pos += frame_len
    return bytes(result)

# Connected NTRIP clients — each entry is a socket
clients = []
clients_lock = threading.Lock()

# Flag to log only the first RTCM3 packet received
first_rtcm_logged = False


def broadcast(data):
    """Send data to all connected NTRIP clients, removing dead ones."""
    with clients_lock:
        dead = []
        for sock in clients:
            try:
                sock.sendall(data)
            except (BrokenPipeError, ConnectionResetError, OSError):
                dead.append(sock)
        for sock in dead:
            clients.remove(sock)
            addr = "unknown"
            try:
                addr = sock.getpeername()
            except Exception:
                pass
            print(f"[ntrip] client disconnected: {addr}", flush=True)
            try:
                sock.close()
            except Exception:
                pass


def strip_tzsp(data):
    """Strip the TZSP header and return the encapsulated frame, or None."""
    if len(data) < 4:
        return None
    # version, type, encapsulated protocol
    _ver, _typ, _proto = struct.unpack("!BBH", data[:4])
    pos = 4
    # Walk tagged fields until end tag (0x01) or padding (0x00)
    while pos < len(data):
        tag_type = data[pos]
        if tag_type == 0x01:  # end tag — no length/value
            pos += 1
            break
        if tag_type == 0x00:  # padding
            pos += 1
            continue
        if pos + 1 >= len(data):
            return None
        tag_len = data[pos + 1]
        pos += 2 + tag_len
    return data[pos:] if pos < len(data) else None


def extract_ip_payload(frame):
    """Given an Ethernet or raw-IP frame, return the transport payload or None."""
    if not frame:
        return None

    # Detect raw IP vs Ethernet: check IP version nibble
    first_nibble = (frame[0] >> 4) & 0xF
    if first_nibble == 4:
        ip_offset = 0  # raw IP
    else:
        ip_offset = 14  # Ethernet header

    if len(frame) < ip_offset + 20:
        return None

    ip_header = frame[ip_offset:]
    version_ihl = ip_header[0]
    if ((version_ihl >> 4) & 0xF) != 4:
        return None
    ihl = (version_ihl & 0xF) * 4
    protocol = ip_header[9]

    transport_offset = ip_offset + ihl

    if protocol == 17:  # UDP — 8-byte header
        if len(frame) < transport_offset + 8:
            return None
        return frame[transport_offset + 8:]
    elif protocol == 6:  # TCP — variable-length header
        if len(frame) < transport_offset + 20:
            return None
        tcp_header = frame[transport_offset:]
        data_offset = ((tcp_header[12] >> 4) & 0xF) * 4
        if len(frame) < transport_offset + data_offset:
            return None
        payload = frame[transport_offset + data_offset:]
        return payload if payload else None

    return None


def tzsp_receiver():
    """Listen for TZSP packets and broadcast RTCM3 data to NTRIP clients."""
    global first_rtcm_logged
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", TZSP_PORT))
    print(f"[tzsp] listening on UDP port {TZSP_PORT}", flush=True)

    while True:
        data, addr = sock.recvfrom(65535)
        frame = strip_tzsp(data)
        if frame is None:
            continue
        payload = extract_ip_payload(frame)
        if payload is None or len(payload) == 0:
            continue
        # Extract and validate RTCM3 frames (preamble + reserved bits + CRC-24Q)
        validated = extract_rtcm3_frames(payload)
        if not validated:
            continue
        if not first_rtcm_logged:
            first_rtcm_logged = True
            print(f"[tzsp] receiving RTCM3 data from {addr} ({len(validated)} bytes)", flush=True)
        broadcast(validated)


SOURCETABLE = (
    "SOURCETABLE 200 OK\r\n"
    "Content-Type: text/plain\r\n"
    "\r\n"
    f"STR;{MOUNT_POINT};{MOUNT_POINT};RTCM 3.3;;;;;0.00;0.00;0;0;;none;N;N;;\r\n"
    "ENDSOURCETABLE\r\n"
)


def handle_ntrip_client(conn, addr):
    """Handle a single NTRIP client connection."""
    try:
        request = conn.recv(4096).decode("ascii", errors="replace")
    except Exception:
        conn.close()
        return

    lines = request.split("\r\n")
    if not lines:
        conn.close()
        return

    parts = lines[0].split()
    if len(parts) < 2:
        conn.close()
        return

    method, path = parts[0], parts[1]

    if method != "GET":
        conn.sendall(b"HTTP/1.0 405 Method Not Allowed\r\n\r\n")
        conn.close()
        return

    if path == "/":
        # Sourcetable request
        conn.sendall(SOURCETABLE.encode())
        conn.close()
        return

    if path == f"/{MOUNT_POINT}":
        print(f"[ntrip] client connected: {addr}", flush=True)
        conn.sendall(b"ICY 200 OK\r\n\r\n")
        with clients_lock:
            clients.append(conn)
        return  # socket stays open — broadcast() will write to it

    conn.sendall(b"HTTP/1.0 404 Not Found\r\n\r\n")
    conn.close()


def ntrip_caster():
    """Accept NTRIP client connections."""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", NTRIP_PORT))
    srv.listen(5)
    print(f"[ntrip] listening on TCP port {NTRIP_PORT}", flush=True)

    while True:
        conn, addr = srv.accept()
        threading.Thread(target=handle_ntrip_client, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    print(f"TZSP-to-NTRIP bridge starting", flush=True)
    print(f"  TZSP receiver : UDP {TZSP_PORT}", flush=True)
    print(f"  NTRIP caster  : TCP {NTRIP_PORT} (mount /{MOUNT_POINT})", flush=True)
    print(flush=True)

    threading.Thread(target=tzsp_receiver, daemon=True).start()
    ntrip_caster()
