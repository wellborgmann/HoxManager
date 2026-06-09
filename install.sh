#!/bin/bash

[ "$(id -u)" -ne 0 ] && echo "Execute como ROOT!" && exit 1

echo "=========================================="
echo "  INICIANDO CONFIGURAÇÃO"
echo "=========================================="
echo ""

export DEBIAN_FRONTEND=noninteractive
mkdir -p /usr/local/bin /usr/local/etc/xray/ssl /etc/xray /etc/hox /usr/local/hox /var/log/xray

apt-get update -qq -y >/dev/null 2>&1 || true
apt-get install -qq -y --no-install-recommends curl ca-certificates unzip openssl git jq lsof net-tools >/dev/null 2>&1 || true

if ! command -v xray >/dev/null 2>&1; then
    echo "  -> Instalando Xray Core (Oficial)..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1 || true
fi

GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
if [ -z "$GO_VERSION" ] || [ "$(printf '%s\n' "$GO_VERSION" "1.18" | sort -V | head -n1)" != "1.18" ]; then
    apt-get remove --purge -qq -y golang-go golang >/dev/null 2>&1 || true
    rm -rf /usr/local/go >/dev/null 2>&1 || true
    wget -q https://go.dev/dl/go1.21.0.linux-amd64.tar.gz -O /tmp/go.tar.gz >/dev/null 2>&1 || true
    tar -C /usr/local -xzf /tmp/go.tar.gz >/dev/null 2>&1 || true
    export PATH="/usr/local/go/bin:$PATH"
    grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null || echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    rm -f /tmp/go.tar.gz >/dev/null 2>&1 || true
fi
export PATH="/usr/local/go/bin:$PATH"

apt-get install -qq -y git >/dev/null 2>&1 || true

SRCDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "/usr/local/hox/server" ] && cp /usr/local/hox/server /usr/local/hox/server.bak 2>/dev/null || true

if [ -f "$SRCDIR/server.go" ]; then
    cd "$SRCDIR" || exit 1
    go mod tidy >/dev/null 2>&1 || true
    go build -ldflags='-s -w' -o /usr/local/hox/server server.go >/dev/null 2>&1 || true
fi

if [ ! -f "/usr/local/etc/xray/ssl/cert.pem" ]; then
    openssl req -x509 -newkey rsa:4096 -keyout /usr/local/etc/xray/ssl/priv.key -out /usr/local/etc/xray/ssl/cert.pem -days 365 -nodes -subj '/C=BR/ST=State/L=City/O=Organization/CN=localhost' >/dev/null 2>&1 || true
fi

chmod 644 /usr/local/etc/xray/ssl/cert.pem >/dev/null 2>&1 || true
chmod 640 /usr/local/etc/xray/ssl/priv.key >/dev/null 2>&1 || true
mkdir -p /usr/local/etc/xray /var/log/xray /etc/xray >/dev/null 2>&1 || true
chown -R nobody:nogroup /usr/local/etc/xray /var/log/xray /etc/xray >/dev/null 2>&1 || true

rm -f /usr/local/etc/xray/config.json /etc/xray/config.json >/dev/null 2>&1 || true

valid_source=""
if [ -f "$SRCDIR/xray-config.json" ]; then
    if jq -e . "$SRCDIR/xray-config.json" >/dev/null 2>&1 && grep -q '"inbounds"' "$SRCDIR/xray-config.json" >/dev/null 2>&1; then
        valid_source="yes"
    fi
fi

if [ "$valid_source" = "yes" ]; then
    tmp_config=$(mktemp) || tmp_config="/tmp/xray_config.tmp"
    jq 'del(.burstObservatory, .dns, .fakedns, .observatory, .reverse, .transport)' "$SRCDIR/xray-config.json" > "$tmp_config" 2>/dev/null || cp "$SRCDIR/xray-config.json" "$tmp_config"
    mv "$tmp_config" /usr/local/etc/xray/config.json 2>/dev/null || true
else
    cat > /usr/local/etc/xray/config.json <<'XRAY_JSON'
{
  "api": {
    "services": ["HandlerService", "LoggerService", "StatsService"],
    "tag": "api"
  },
  "inbounds": [
    {
      "tag": "api",
      "port": 1080,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "listen": "127.0.0.1"
    },
    {
      "tag": "inbound-hox",
      "port": 4430,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "headers": null,
          "host": "",
          "mode": "packet",
          "noSSEHeader": false,
          "path": "/",
          "scMaxBufferedPosts": 30,
          "scMaxEachPostBytes": "1000000",
          "scStreamUpServerSecs": "20-80",
          "xPaddingBytes": "100-1000"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "ip": ["geoip:private"],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "protocol": ["bittorrent"],
        "type": "field"
      }
    ]
  },
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true
    }
  },
  "stats": {}
}
XRAY_JSON
fi

cp /usr/local/etc/xray/config.json /etc/xray/config.json >/dev/null 2>&1 || true
chmod 644 /usr/local/etc/xray/config.json /etc/xray/config.json >/dev/null 2>&1 || true

cat > /etc/systemd/system/xray.service <<'XRAY_SVC'
[Unit]
Description=Serviço Suplementar 1
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
XRAY_SVC

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable xray.service >/dev/null 2>&1 || true
systemctl restart xray.service >/dev/null 2>&1 || true
sleep 3

cp "$SRCDIR/hox.sh" /usr/local/bin/hox >/dev/null 2>&1 || true
cp "$SRCDIR/xray-config.json" /usr/local/hox/ >/dev/null 2>&1 || true
chmod +x /usr/local/bin/hox /usr/local/hox/server >/dev/null 2>&1 || true

cat > /usr/local/hox/start.sh <<'STARTSH'
#!/bin/bash
PORTS=$(jq -r '.tcp | join(",")' /etc/hox/ports.json 2>/dev/null)
UDPGW=$(jq -r '.udp | join(",")' /etc/hox/ports.json 2>/dev/null)
[ -z "$PORTS" ] && PORTS=443
[ -z "$UDPGW" ] && UDPGW=7300
exec /usr/local/hox/server -ports "$PORTS" -udpgw "$UDPGW"
STARTSH
chmod +x /usr/local/hox/start.sh >/dev/null 2>&1 || true

cat > /etc/systemd/system/hox.service <<'HOXSVC'
[Unit]
Description=Serviço Principal
After=network.target xray.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/usr/local/hox
ExecStart=/usr/local/hox/start.sh
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
HOXSVC

# [ ! -f "/etc/hox/users.db" ] && echo '{"users":[]}' > "/etc/hox/users.db" (REMOVED)

[ ! -f "/etc/hox/ports.json" ] && echo '{"tcp":["443"],"udp":["7300"]}' > "/etc/hox/ports.json"

for port in 443 80 8080 8443 7300; do
    iptables -I INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1 || true
    iptables -I INPUT -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1 || true
done

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable hox.service >/dev/null 2>&1 || true
systemctl restart hox.service >/dev/null 2>&1 || true
sleep 2

echo ""
echo "=========================================="
echo "  VERIFICAÇÃO FINAL"
echo "=========================================="
echo ""

if systemctl is-active --quiet xray; then
    echo "✓ Serviço 1 ativo"
else
    echo "✗ Serviço 1 inativo"
fi

if systemctl is-active --quiet hox; then
    echo "✓ Serviço 2 ativo"
else
    echo "✗ Serviço 2 inativo"
fi

echo ""
if timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/4430' 2>/dev/null; then
    echo "✓ Conectividade OK"
else
    echo "✗ Conectividade com problema"
fi

echo ""
echo "=========================================="
echo "  INSTALAÇÃO CONCLUÍDA"
echo "=========================================="
echo ""
echo "Digite 'hox' para gerenciar."
echo ""
