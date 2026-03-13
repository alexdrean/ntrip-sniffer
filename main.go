package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	fmt.Println("TZSP-to-NTRIP bridge starting")
	fmt.Println("  TZSP receiver : UDP 37008")
	fmt.Println("  NTRIP caster  : TCP 2101")
	fmt.Println("  Mountpoints   : dynamic (from TZSP source IPs)")

	loadUsers()
	initCRCTable()
	fmt.Println()

	clients := newClientRegistry()
	asm := newStreamAssembler()
	go startTZSP(clients, asm)
	go startCaster(clients)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	fmt.Println("\nshutting down")
}
