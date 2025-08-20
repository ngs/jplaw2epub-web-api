package handlers

import (
	"log"
	"net"
	"os"
	"strconv"
)

func DeterminePort(portFlag string) string {
	if portFlag != "" {
		return portFlag
	}
	if envPort := os.Getenv("PORT"); envPort != "" {
		return envPort
	}
	return FindAvailablePort()
}

func FindAvailablePort() string {
	listener, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		log.Fatalf("Failed to find available port: %v", err)
	}
	tcpAddr, ok := listener.Addr().(*net.TCPAddr)
	if !ok {
		log.Fatalf("Failed to get TCP address from listener")
	}
	port := strconv.Itoa(tcpAddr.Port)
	if err := listener.Close(); err != nil {
		log.Printf("Warning: failed to close listener: %v", err)
	}
	return port
}
