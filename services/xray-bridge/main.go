package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// SessionEntry holds active connection telemetry
type SessionEntry struct {
	ID     string `json:"id"`
	Port   string `json:"port"`
	IP     string `json:"ip"`
	Subnet string `json:"subnet"`
	Mode   string `json:"mode"`
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	Open   bool   `json:"open"`
	Ts     int64  `json:"ts"`
}

var sessionMap sync.Map
var mapDirty = make(chan struct{}, 1)
var stateFile = "/run/alyan-xray-sessions.json"

type byteCounter struct {
	w     io.Writer
	entry *SessionEntry
}

var bufPool = sync.Pool{
	New: func() interface{} {
		b := make([]byte, 65536)
		return &b
	},
}

func copyBuffer(dst io.Writer, src io.Reader) (int64, error) {
	bp := bufPool.Get().(*[]byte)
	defer bufPool.Put(bp)
	return io.CopyBuffer(dst, struct{ io.Reader }{src}, *bp)
}

func (bc *byteCounter) Write(p []byte) (int, error) {
	n, err := bc.w.Write(p)
	if n > 0 && bc.entry != nil {
		atomic.AddInt64(&bc.entry.Bytes, int64(n))
		atomic.StoreInt64(&bc.entry.Ts, time.Now().Unix())
	}
	return n, err
}

func notifyDirty() {
	select {
	case mapDirty <- struct{}{}:
	default:
	}
}

// Subnet helper: /16 for IPv4 to merge CGNAT pre-flight pings
func getSubnet(ipStr string) string {
	ip := net.ParseIP(ipStr)
	if ip == nil {
		return ipStr
	}
	if ip4 := ip.To4(); ip4 != nil {
		return fmt.Sprintf("%d.%d.0.0/16", ip4[0], ip4[1])
	}
	return ipStr
}

func flushState() {
	now := time.Now().Unix()

	var activeEntries []*SessionEntry
	sessionMap.Range(func(k, v interface{}) bool {
		se := v.(*SessionEntry)
		if se.Open {
			activeEntries = append(activeEntries, se)
		}
		return true
	})

	// Filter out ephemeral pre-flight probe sockets if a primary streaming socket exists in the same subnet
	snap := make(map[string]SessionEntry)
	for _, se := range activeEntries {
		b := atomic.LoadInt64(&se.Bytes)
		// Check if this is a tiny probe (< 4KB) with a larger streaming socket already in the same subnet
		isProbe := b < 4096 && (now-se.Ts < 6)
		hasLargerInSubnet := false
		if isProbe {
			for _, other := range activeEntries {
				if other != se && other.Subnet == se.Subnet && atomic.LoadInt64(&other.Bytes) > b {
					hasLargerInSubnet = true
					break
				}
			}
		}
		if hasLargerInSubnet {
			continue // suppress the short-lived probe
		}

		snap[se.Port] = SessionEntry{
			ID:     se.ID,
			Port:   se.Port,
			IP:     se.IP,
			Subnet: se.Subnet,
			Mode:   se.Mode,
			Path:   se.Path,
			Bytes:  b,
			Open:   true,
			Ts:     atomic.LoadInt64(&se.Ts),
		}
	}

	if b, err := json.MarshalIndent(snap, "", "  "); err == nil {
		tmp := stateFile + ".tmp"
		if os.WriteFile(tmp, b, 0644) == nil {
			_ = os.Rename(tmp, stateFile)
		}
	}
}

func stateWriterDaemon() {
	tk := time.NewTicker(250 * time.Millisecond)
	defer tk.Stop()
	for {
		select {
		case <-mapDirty:
			time.Sleep(20 * time.Millisecond)
			flushState()
		case <-tk.C:
			flushState()
		}
	}
}

func tuneTCP(c net.Conn) {
	if tc, ok := c.(*net.TCPConn); ok {
		_ = tc.SetNoDelay(true)
		_ = tc.SetKeepAlive(true)
		_ = tc.SetKeepAlivePeriod(3 * time.Second)
		if rc, err := tc.SyscallConn(); err == nil {
			_ = rc.Control(func(fd uintptr) {
				_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_NODELAY, 1)
				_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, 6, 3)      // TCP_KEEPCNT = 3
				_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, 5, 2)      // TCP_KEEPINTVL = 2
				_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, 18, 8000) // TCP_USER_TIMEOUT = 8s
			})
		}
	}
}

func cleanIP(s string) string {
	s = strings.TrimSpace(s)
	if h, _, err := net.SplitHostPort(s); err == nil {
		s = h
	}
	return strings.TrimPrefix(strings.Trim(s, "[]"), "::ffff:")
}

func extractRealIP(headerBlock string, fallback string) string {
	lines := strings.Split(headerBlock, "\r\n")
	for _, ln := range lines {
		lower := strings.ToLower(ln)
		if strings.HasPrefix(lower, "cf-connecting-ip:") {
			ip := cleanIP(ln[17:])
			if ip != "" && ip != "127.0.0.1" {
				return ip
			}
		}
		if strings.HasPrefix(lower, "x-forwarded-for:") {
			parts := strings.Split(ln[16:], ",")
			if len(parts) > 0 {
				ip := cleanIP(parts[len(parts)-1])
				if ip != "" && ip != "127.0.0.1" {
					return ip
				}
			}
		}
		if strings.HasPrefix(lower, "x-real-ip:") {
			ip := cleanIP(ln[10:])
			if ip != "" && ip != "127.0.0.1" {
				return ip
			}
		}
	}
	return fallback
}

func matchTarget(firstLine string) (string, string) {
	lower := strings.ToLower(firstLine)
	if strings.Contains(lower, "/alyan-vless") || strings.Contains(lower, "/vless") {
		return "127.0.0.1:20001", "VLESS-WS"
	}
	if strings.Contains(lower, "/alyan-vmess") || strings.Contains(lower, "/vmess") {
		return "127.0.0.1:20002", "VMESS-WS"
	}
	if strings.Contains(lower, "/alyan-trojan") || strings.Contains(lower, "/trojan") {
		return "127.0.0.1:20003", "TROJAN-WS"
	}
	if strings.Contains(lower, "/alyan-xhttp") || strings.Contains(lower, "/xhttp") {
		return "127.0.0.1:20004", "VLESS-XHTTP"
	}
	if strings.Contains(lower, "/alyan-vless-grpc") || strings.Contains(lower, "grpc") {
		return "127.0.0.1:20005", "VLESS-GRPC"
	}
	return "127.0.0.1:20001", "VLESS-WS"
}

func handleClient(client net.Conn) {
	defer client.Close()
	tuneTCP(client)

	rawIP := cleanIP(client.RemoteAddr().String())

	_ = client.SetReadDeadline(time.Now().Add(3000 * time.Millisecond))
	buf := make([]byte, 8192)
	n, err := client.Read(buf)
	_ = client.SetReadDeadline(time.Time{})
	if err != nil || n == 0 {
		return
	}
	data := buf[:n]

	// Strip incoming PROXY v1/v2 if passed
	if bytes.HasPrefix(data, []byte("PROXY ")) {
		if idx := bytes.Index(data, []byte("\r\n")); idx != -1 {
			fields := strings.Fields(string(data[:idx]))
			if len(fields) >= 3 && fields[2] != "127.0.0.1" {
				rawIP = fields[2]
			}
			data = data[idx+2:]
		}
	}

	reqStr := string(data)
	firstLine := strings.TrimSpace(strings.Split(reqStr, "\n")[0])
	realIP := extractRealIP(reqStr, rawIP)

	targetAddr, mode := matchTarget(firstLine)

	flFields := strings.Fields(firstLine)
	reqPath := "/alyan-vless"
	if len(flFields) >= 2 {
		reqPath = flFields[1]
	}

	target, err := net.DialTimeout("tcp", targetAddr, 3*time.Second)
	if err != nil {
		fmt.Printf("[Bridge Error] Dial Xray (%s) failed: %v\n", targetAddr, err)
		return
	}
	tuneTCP(target)
	defer target.Close()

	_, lport, _ := net.SplitHostPort(target.LocalAddr().String())
	sessionID := strings.ToLower(mode) + "-" + lport
	subnet := getSubnet(realIP)

	entry := &SessionEntry{
		ID:     sessionID,
		Port:   lport,
		IP:     realIP,
		Subnet: subnet,
		Mode:   mode,
		Path:   reqPath,
		Bytes:  0,
		Open:   true,
		Ts:     time.Now().Unix(),
	}
	sessionMap.Store(lport, entry)
	notifyDirty()

	defer func() {
		entry.Open = false
		sessionMap.Delete(lport)
		notifyDirty()
	}()

	// Forward initial handshake to Xray
	_, _ = target.Write(data)

	done := make(chan struct{}, 2)
	go func() {
		_, _ = copyBuffer(&byteCounter{w: target, entry: entry}, client)
		_ = target.Close()
		done <- struct{}{}
	}()
	go func() {
		_, _ = copyBuffer(&byteCounter{w: client, entry: entry}, target)
		_ = client.Close()
		done <- struct{}{}
	}()
	<-done
}

func main() {
	runtime.GOMAXPROCS(runtime.NumCPU())
	listenAddr := "127.0.0.1:8885"
	if len(os.Args) > 1 {
		listenAddr = os.Args[1]
	}
	if len(os.Args) > 2 {
		stateFile = os.Args[2]
	}

	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to bind %s: %v\n", listenAddr, err)
		os.Exit(1)
	}
	defer ln.Close()

	go stateWriterDaemon()

	fmt.Printf("🔥 Alyan Xray Bridge active on %s\n", listenAddr)
	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleClient(conn)
	}
}
