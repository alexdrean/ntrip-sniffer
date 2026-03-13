package main

import (
	"fmt"
	"net"
	"sync"
)

const tzspPort = 37008

func startTZSP(clients *clientRegistry, asm *streamAssembler) {
	addr := net.UDPAddr{Port: tzspPort}
	conn, err := net.ListenUDP("udp", &addr)
	if err != nil {
		fmt.Printf("[tzsp] failed to listen: %v\n", err)
		return
	}
	defer conn.Close()
	fmt.Printf("[tzsp] listening on UDP port %d\n", tzspPort)

	var loggedMu sync.Mutex
	logged := make(map[string]bool)

	buf := make([]byte, 65536)
	for {
		n, remote, err := conn.ReadFromUDP(buf)
		if err != nil {
			continue
		}
		processPacket(buf[:n], remote, clients, asm, &loggedMu, logged)
	}
}

func processPacket(data []byte, remote *net.UDPAddr, clients *clientRegistry, asm *streamAssembler, loggedMu *sync.Mutex, logged map[string]bool) {
	frame, ok := stripTZSP(data)
	if !ok {
		return
	}

	srcIP, validated, ok := asm.process(frame)
	if !ok {
		return
	}

	loggedMu.Lock()
	if !logged[srcIP] {
		logged[srcIP] = true
		loggedMu.Unlock()
		fmt.Printf("[tzsp] RTCM3 source %s (via %s, %d bytes) -> /%s\n",
			srcIP, remote.String(), len(validated), srcIP)
		clients.notifyMountpoint(srcIP)
	} else {
		loggedMu.Unlock()
	}

	clients.broadcast(srcIP, validated)
}
