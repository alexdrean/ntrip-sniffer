package main

import (
	"hash/fnv"
	"sync"
	"time"
)

type streamState struct {
	buf      []byte
	nextSeq  uint32
	inited   bool
	lastSeen time.Time
}

type streamAssembler struct {
	streamsMu sync.Mutex
	streams   map[string]*streamState

	dedupMu sync.Mutex
	dedup   map[uint64]time.Time
}

func newStreamAssembler() *streamAssembler {
	a := &streamAssembler{
		streams: make(map[string]*streamState),
		dedup:   make(map[uint64]time.Time),
	}
	go a.cleanupLoop()
	return a
}

func (a *streamAssembler) cleanupLoop() {
	ticker := time.NewTicker(30 * time.Second)
	for range ticker.C {
		now := time.Now()

		a.dedupMu.Lock()
		for h, t := range a.dedup {
			if now.Sub(t) > 5*time.Second {
				delete(a.dedup, h)
			}
		}
		a.dedupMu.Unlock()

		a.streamsMu.Lock()
		for ip, s := range a.streams {
			if now.Sub(s.lastSeen) > 60*time.Second {
				delete(a.streams, ip)
			}
		}
		a.streamsMu.Unlock()
	}
}

// process takes a raw frame (after TZSP stripping) and returns
// (srcIP, deduplicated RTCM3 frames, ok).
func (a *streamAssembler) process(frame []byte) (string, []byte, bool) {
	srcIP, proto, seq, payload, ok := extractIPPayloadEx(frame)
	if !ok || len(payload) == 0 {
		return "", nil, false
	}

	var frames []byte
	if proto == 17 { // UDP — no reassembly needed
		frames, _ = extractFrames(payload)
	} else { // TCP — reassemble stream
		frames = a.reassemble(srcIP, seq, payload)
	}

	if len(frames) == 0 {
		return srcIP, nil, false
	}

	deduped := a.dedupFrames(frames)
	if len(deduped) == 0 {
		return srcIP, nil, false
	}

	return srcIP, deduped, true
}

func (a *streamAssembler) reassemble(srcIP string, seq uint32, payload []byte) []byte {
	a.streamsMu.Lock()
	defer a.streamsMu.Unlock()

	state, exists := a.streams[srcIP]
	if !exists {
		state = &streamState{}
		a.streams[srcIP] = state
	}
	state.lastSeen = time.Now()

	endSeq := seq + uint32(len(payload))

	if !state.inited {
		state.nextSeq = seq
		state.inited = true
	}

	// Entirely retransmitted — skip
	if seqLE(endSeq, state.nextSeq) {
		return nil
	}

	// Partial retransmission — trim leading overlap
	if seqBefore(seq, state.nextSeq) {
		trim := state.nextSeq - seq
		if int(trim) >= len(payload) {
			return nil
		}
		payload = payload[trim:]
		seq = state.nextSeq
	}

	// Gap in sequence — reset buffer, start fresh
	if seq != state.nextSeq {
		state.buf = state.buf[:0]
		state.nextSeq = seq
	}

	state.buf = append(state.buf, payload...)
	state.nextSeq = seq + uint32(len(payload))

	frames, remaining := extractFrames(state.buf)

	if len(remaining) > 0 {
		newBuf := make([]byte, len(remaining))
		copy(newBuf, remaining)
		state.buf = newBuf
	} else {
		state.buf = state.buf[:0]
	}

	// Prevent unbounded buffer growth from garbage
	if len(state.buf) > 8192 {
		state.buf = state.buf[:0]
	}

	return frames
}

// seqBefore returns true if a comes before b in TCP sequence space (handles wrap).
func seqBefore(a, b uint32) bool {
	return int32(a-b) < 0
}

// seqLE returns true if a <= b in TCP sequence space.
func seqLE(a, b uint32) bool {
	return a == b || seqBefore(a, b)
}

func (a *streamAssembler) dedupFrames(data []byte) []byte {
	a.dedupMu.Lock()
	defer a.dedupMu.Unlock()

	now := time.Now()
	var result []byte

	for len(data) >= 6 {
		if data[0] != 0xD3 {
			data = data[1:]
			continue
		}
		length := int(data[1]&0x03)<<8 | int(data[2])
		totalLen := 3 + length + 3
		if len(data) < totalLen {
			break
		}
		frame := data[:totalLen]
		h := hashFrame(frame)
		if _, seen := a.dedup[h]; !seen {
			a.dedup[h] = now
			result = append(result, frame...)
		}
		data = data[totalLen:]
	}

	return result
}

func hashFrame(data []byte) uint64 {
	h := fnv.New64a()
	h.Write(data)
	return h.Sum64()
}
