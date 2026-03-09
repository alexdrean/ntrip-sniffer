package main

var crc24qTable [256]uint32

const crc24qPoly = 0x1864CFB

func initCRCTable() {
	for i := 0; i < 256; i++ {
		crc := uint32(i) << 16
		for bit := 0; bit < 8; bit++ {
			crc <<= 1
			if crc&0x1000000 != 0 {
				crc ^= crc24qPoly
			}
		}
		crc24qTable[i] = crc & 0xFFFFFF
	}
}

func crc24q(data []byte) uint32 {
	var crc uint32
	for _, b := range data {
		index := ((crc >> 16) ^ uint32(b)) & 0xFF
		crc = (crc24qTable[index] ^ (crc << 8)) & 0xFFFFFF
	}
	return crc
}

// extractFrames extracts and validates RTCM3 frames from a payload.
func extractFrames(payload []byte) []byte {
	var result []byte
	for len(payload) > 0 {
		// Scan for preamble
		if payload[0] != 0xD3 {
			payload = payload[1:]
			continue
		}
		if len(payload) < 3 {
			break
		}
		// Check reserved bits are zero (upper 6 bits of second byte)
		if payload[1]&0xFC != 0 {
			payload = payload[1:]
			continue
		}
		length := int(payload[1]&0x03)<<8 | int(payload[2])
		totalLen := 3 + length + 3 // header + body + CRC
		if len(payload) < totalLen {
			break
		}
		body := payload[3 : 3+length]
		crcBytes := payload[3+length : totalLen]
		expectedCRC := uint32(crcBytes[0])<<16 | uint32(crcBytes[1])<<8 | uint32(crcBytes[2])
		header := payload[:3]
		toCheck := make([]byte, 3+length)
		copy(toCheck, header)
		copy(toCheck[3:], body)
		if crc24q(toCheck) == expectedCRC {
			result = append(result, payload[:totalLen]...)
			payload = payload[totalLen:]
		} else {
			payload = payload[1:]
		}
	}
	return result
}
