package main

import (
	"fmt"
	"net"
	"time"
)

const ntripPort = 2101

func startCaster(clients *clientRegistry) {
	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", ntripPort))
	if err != nil {
		fmt.Printf("[ntrip] failed to listen: %v\n", err)
		return
	}
	defer ln.Close()
	fmt.Printf("[ntrip] listening on TCP port %d\n", ntripPort)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleClient(conn, clients)
	}
}

func handleClient(conn net.Conn, clients *clientRegistry) {
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))

	buf := make([]byte, 4096)
	n, err := conn.Read(buf)
	if err != nil {
		return
	}

	req, ok := parseNTRIPRequest(buf[:n])
	if !ok {
		return
	}

	switch {
	case req.method != "GET":
		conn.Write([]byte("HTTP/1.0 405 Method Not Allowed\r\n\r\n"))

	case req.path == "/":
		sendSourcetable(conn, clients)

	case len(req.path) > 1:
		mountpoint := req.path[1:] // strip leading /
		if !checkAuth(req.auth) {
			conn.Write([]byte("HTTP/1.0 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"NTRIP\"\r\n\r\n"))
			return
		}
		startStream(conn, mountpoint, clients)

	default:
		conn.Write([]byte("HTTP/1.0 404 Not Found\r\n\r\n"))
	}
}

func sendSourcetable(conn net.Conn, clients *clientRegistry) {
	mountpoints := clients.getMountpoints()
	resp := buildSourcetable(mountpoints, isAuthRequired())
	conn.Write(resp)
}

func startStream(conn net.Conn, mountpoint string, clients *clientRegistry) {
	addr := conn.RemoteAddr().String()
	fmt.Printf("[ntrip] client connected: %s -> /%s\n", addr, mountpoint)

	conn.Write([]byte("ICY 200 OK\r\n\r\n"))
	conn.SetReadDeadline(time.Time{}) // clear deadline

	ch := make(chan []byte, 64)
	clients.registerClient(ch, addr, mountpoint)
	defer func() {
		clients.unregisterClient(ch)
		fmt.Printf("[ntrip] client disconnected: %s (was on /%s)\n", addr, mountpoint)
	}()

	for data := range ch {
		conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
		_, err := conn.Write(data)
		if err != nil {
			return
		}
	}
}
