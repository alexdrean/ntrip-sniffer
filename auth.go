package main

import (
	"fmt"
	"os"
	"strings"
	"sync"
)

const usersFile = "users.conf"

var (
	authUsers   map[string]string // nil means auth disabled
	authUsersMu sync.RWMutex
)

func loadUsers() {
	data, err := os.ReadFile(usersFile)
	if err != nil {
		authUsersMu.Lock()
		authUsers = nil
		authUsersMu.Unlock()
		fmt.Printf("[auth] no %s found, authentication disabled\n", usersFile)
		return
	}
	users := parseUsers(string(data))
	authUsersMu.Lock()
	authUsers = users
	authUsersMu.Unlock()
	fmt.Printf("[auth] loaded %d users from %s\n", len(users), usersFile)
}

func parseUsers(data string) map[string]string {
	users := make(map[string]string)
	for _, line := range strings.Split(data, "\n") {
		line = strings.TrimRight(line, "\r")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		user, pass, ok := strings.Cut(line, ":")
		if ok && user != "" {
			users[user] = pass
		}
	}
	return users
}

func checkAuth(auth *basicAuth) bool {
	authUsersMu.RLock()
	defer authUsersMu.RUnlock()
	if authUsers == nil {
		return true
	}
	if auth == nil {
		return false
	}
	pass, ok := authUsers[auth.user]
	return ok && pass == auth.pass
}

func isAuthRequired() bool {
	authUsersMu.RLock()
	defer authUsersMu.RUnlock()
	return authUsers != nil
}
