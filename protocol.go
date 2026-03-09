package main

import (
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"strings"
)

// stripTZSP strips the TZSP header and tagged fields, returning the encapsulated frame.
func stripTZSP(data []byte) ([]byte, bool) {
	if len(data) < 4 {
		return nil, false
	}
	// Skip Ver, Type, Proto(16-bit)
	return walkTags(data[4:])
}

func walkTags(data []byte) ([]byte, bool) {
	for len(data) > 0 {
		switch data[0] {
		case 0x01: // End tag
			return data[1:], true
		case 0x00: // Padding
			data = data[1:]
		default:
			if len(data) < 2 {
				return nil, false
			}
			tagLen := int(data[1])
			if len(data) < 2+tagLen {
				return nil, false
			}
			data = data[2+tagLen:]
		}
	}
	return nil, false
}

// extractIPPayload extracts the source IP string and transport payload from
// an Ethernet or raw-IP frame.
func extractIPPayload(frame []byte) (srcIP string, payload []byte, ok bool) {
	// Try raw IPv4 first
	if len(frame) >= 20 && (frame[0]>>4) == 4 {
		return extractFromIPv4(frame)
	}
	// Try Ethernet + IPv4
	if len(frame) >= 34 && (frame[14]>>4) == 4 {
		return extractFromIPv4(frame[14:])
	}
	return "", nil, false
}

func extractFromIPv4(ip []byte) (string, []byte, bool) {
	if len(ip) < 20 {
		return "", nil, false
	}
	ihl := int(ip[0] & 0x0F)
	headerLen := ihl * 4
	if len(ip) < headerLen {
		return "", nil, false
	}
	proto := ip[9]
	srcIP := fmt.Sprintf("%d.%d.%d.%d", ip[12], ip[13], ip[14], ip[15])
	transportData := ip[headerLen:]

	payload, ok := extractTransport(proto, transportData)
	if !ok {
		return "", nil, false
	}
	return srcIP, payload, true
}

func extractTransport(proto byte, data []byte) ([]byte, bool) {
	switch proto {
	case 17: // UDP
		if len(data) < 8 {
			return nil, false
		}
		return data[8:], true
	case 6: // TCP
		if len(data) < 20 {
			return nil, false
		}
		offset := int(data[12]>>4) * 4
		if len(data) < offset {
			return nil, false
		}
		payload := data[offset:]
		if len(payload) == 0 {
			return nil, false
		}
		return payload, true
	default:
		return nil, false
	}
}

// ntripRequest holds a parsed NTRIP/HTTP request.
type ntripRequest struct {
	method string
	path   string
	auth   *basicAuth // nil if no auth
}

type basicAuth struct {
	user string
	pass string
}

// parseNTRIPRequest parses an NTRIP/HTTP request from raw bytes.
func parseNTRIPRequest(data []byte) (*ntripRequest, bool) {
	lines := strings.Split(string(data), "\r\n")
	if len(lines) == 0 {
		return nil, false
	}
	parts := strings.SplitN(lines[0], " ", 3)
	if len(parts) < 2 {
		return nil, false
	}
	req := &ntripRequest{
		method: parts[0],
		path:   parts[1],
		auth:   findAuthHeader(lines[1:]),
	}
	return req, true
}

func findAuthHeader(headers []string) *basicAuth {
	for _, h := range headers {
		var encoded string
		if strings.HasPrefix(h, "Authorization: Basic ") {
			encoded = strings.TrimPrefix(h, "Authorization: Basic ")
		} else if strings.HasPrefix(h, "Authorization:Basic ") {
			encoded = strings.TrimPrefix(h, "Authorization:Basic ")
		} else {
			continue
		}
		decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(encoded))
		if err != nil {
			return nil
		}
		user, pass, ok := strings.Cut(string(decoded), ":")
		if !ok || user == "" {
			return nil
		}
		return &basicAuth{user: user, pass: pass}
	}
	return nil
}

// formatAddr formats a net.Addr-style address from IP + port.
func formatAddr(ip string, port int) string {
	return fmt.Sprintf("%s:%d", ip, port)
}

// sourcetableEntry builds an NTRIP sourcetable STR entry.
func sourcetableEntry(mp string, authRequired bool) string {
	authField := "N"
	if authRequired {
		authField = "B"
	}
	return fmt.Sprintf("STR;%s;RTCM3;RTCM 3.3;;;;;0.00;0.00;0;0;;none;%s;N;;\r\n", mp, authField)
}

// buildSourcetable returns a full NTRIP sourcetable response.
func buildSourcetable(mountpoints []string, authRequired bool) []byte {
	var b strings.Builder
	b.WriteString("SOURCETABLE 200 OK\r\n")
	b.WriteString("Content-Type: text/plain\r\n")
	b.WriteString("\r\n")
	for _, mp := range mountpoints {
		b.WriteString(sourcetableEntry(mp, authRequired))
	}
	b.WriteString("ENDSOURCETABLE\r\n")
	return []byte(b.String())
}

// ntoa converts a 4-byte IP to string (for IPs stored as uint32 in network byte order).
func ntoa(ip uint32) string {
	b := make([]byte, 4)
	binary.BigEndian.PutUint32(b, ip)
	return fmt.Sprintf("%d.%d.%d.%d", b[0], b[1], b[2], b[3])
}
