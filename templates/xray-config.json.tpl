{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "connIdle": 30,
        "bufferSize": 1024,
        "uplinkOnly": 15,
        "downlinkOnly": 30,
        "handshake": 10
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "api",
      "port": 10085,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    },
    {
      "tag": "vless-ws",
      "port": 20001,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": {{VLESS_CLIENTS}},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/alyan-vless",
          "heartbeatPeriod": 2
        },
        "sockopt": {
          "trustedXForwardedFor": ["CF-Connecting-IP", "X-Forwarded-For", "X-Real-IP"]
        }
      }
    },
    {
      "tag": "vmess-ws",
      "port": 20002,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": {{VMESS_CLIENTS}}
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/alyan-vmess",
          "heartbeatPeriod": 2
        },
        "sockopt": {
          "trustedXForwardedFor": ["CF-Connecting-IP", "X-Forwarded-For", "X-Real-IP"]
        }
      }
    },
    {
      "tag": "trojan-ws",
      "port": 20003,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": {{TROJAN_CLIENTS}}
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/alyan-trojan",
          "heartbeatPeriod": 2
        },
        "sockopt": {
          "trustedXForwardedFor": ["CF-Connecting-IP", "X-Forwarded-For", "X-Real-IP"]
        }
      }
    },
    {
      "tag": "vless-xhttp",
      "port": 20004,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": {{VLESS_CLIENTS}},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/alyan-xhttp",
          "mode": "stream-up"
        },
        "sockopt": {
          "trustedXForwardedFor": ["CF-Connecting-IP", "X-Forwarded-For", "X-Real-IP"]
        }
      }
    },
    {
      "tag": "vless-grpc",
      "port": 20005,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": {{VLESS_CLIENTS}},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "alyan-vless-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      }
    ]
  }
}
