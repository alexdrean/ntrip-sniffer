package main

import "sync"

type clientInfo struct {
	ch         chan []byte
	addr       string
	mountpoint string
}

type clientRegistry struct {
	mu          sync.RWMutex
	clients     map[chan []byte]*clientInfo
	mountpoints map[string]bool
}

func newClientRegistry() *clientRegistry {
	return &clientRegistry{
		clients:     make(map[chan []byte]*clientInfo),
		mountpoints: make(map[string]bool),
	}
}

func (r *clientRegistry) registerClient(ch chan []byte, addr, mountpoint string) {
	r.mu.Lock()
	r.clients[ch] = &clientInfo{ch: ch, addr: addr, mountpoint: mountpoint}
	r.mu.Unlock()
}

func (r *clientRegistry) unregisterClient(ch chan []byte) {
	r.mu.Lock()
	delete(r.clients, ch)
	r.mu.Unlock()
	close(ch)
}

func (r *clientRegistry) broadcast(mountpoint string, data []byte) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	for _, c := range r.clients {
		if c.mountpoint == mountpoint {
			select {
			case c.ch <- data:
			default:
				// Drop if client is too slow
			}
		}
	}
}

func (r *clientRegistry) notifyMountpoint(mp string) {
	r.mu.Lock()
	r.mountpoints[mp] = true
	r.mu.Unlock()
}

func (r *clientRegistry) getMountpoints() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	mps := make([]string, 0, len(r.mountpoints))
	for mp := range r.mountpoints {
		mps = append(mps, mp)
	}
	return mps
}
