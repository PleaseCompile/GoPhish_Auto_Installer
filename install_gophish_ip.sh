#!/usr/bin/env bash
################################################################################
# GoPhish Auto Installer (with Auto IP Detection)
# Usage: 
#   sudo bash install_gophish_ip.sh
#   # Or override IP: sudo GOPHISH_IP=1.2.3.4 bash install_gophish_ip.sh
################################################################################
set -euo pipefail

# Function to detect public IP
detect_public_ip() {
  local ip=""
  
  # Try AWS EC2 metadata
  if command -v curl >/dev/null 2>&1; then
    ip=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  fi
  
  # Try GCP metadata
  if command -v curl >/dev/null 2>&1; then
    ip=$(curl -s --max-time 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || echo "")
    if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  fi
  
  # Try ipify.org
  if command -v curl >/dev/null 2>&1; then
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
    if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  fi
  
  # Try ifconfig.co
  if command -v curl >/dev/null 2>&1; then
    ip=$(curl -s --max-time 5 https://ifconfig.co 2>/dev/null || echo "")
    if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  fi
  
  # Try ifconfig.me
  if command -v curl >/dev/null 2>&1; then
    ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  fi
  
  # All methods failed
  return 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)"
  exit 1
fi

# Determine IP (from env var or auto-detect)
if [ -n "${GOPHISH_IP:-}" ]; then
  IP="$GOPHISH_IP"
  echo ">> Using IP from GOPHISH_IP environment variable: ${IP}"
else
  echo ">> Auto-detecting public IP address..."
  if ! IP=$(detect_public_ip); then
    echo "ERROR: Could not detect public IP address automatically."
    echo "Please set it manually: sudo GOPHISH_IP=YOUR_IP bash $0"
    exit 2
  fi
  echo ">> Detected public IP: ${IP}"
fi

# Validate IP format
if ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Invalid IP address format: ${IP}"
  exit 3
fi

# Configuration
GOPHISH_USER="gophish"
INSTALL_DIR="/opt/gophish"
SSL_DIR="/etc/ssl/gophish"
SERVICE_FILE="/etc/systemd/system/gophish.service"
TMPDIR=$(mktemp -d)

echo "========================================="
echo "  GoPhish Auto Installer"
echo "  IP: ${IP}"
echo "========================================="

echo
echo "[1/8] Installing dependencies..."
apt-get update -qq
apt-get install -y curl unzip jq ca-certificates openssl

echo
echo "[2/8] Creating gophish user..."
if ! id -u "${GOPHISH_USER}" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/${GOPHISH_USER} -s /usr/sbin/nologin ${GOPHISH_USER}
  echo "  ✓ User '${GOPHISH_USER}' created"
else
  echo "  ✓ User '${GOPHISH_USER}' already exists"
fi

echo
echo "[3/8] Downloading latest GoPhish release..."
API_JSON=$(curl -s "https://api.github.com/repos/gophish/gophish/releases/latest")
GOPHISH_TAG=$(echo "$API_JSON" | jq -r .tag_name)
echo "  Latest version: ${GOPHISH_TAG}"

# Find linux 64-bit asset
GOPHISH_ZIP_URL=$(echo "$API_JSON" | jq -r '.assets[] | select(.name | test("linux.*64|linux.*amd64|linux-64|linux64"; "i")) | .browser_download_url' | head -n1)

if [ -z "$GOPHISH_ZIP_URL" ]; then
  echo "  ERROR: Could not find Linux 64-bit asset from GitHub API"
  echo "  Please check https://github.com/gophish/gophish/releases and download manually"
  exit 4
fi

echo "  Downloading: $GOPHISH_ZIP_URL"
cd "$TMPDIR"
curl -L -o gophish.zip "$GOPHISH_ZIP_URL"
unzip -q gophish.zip -d gophish_unpacked

echo
echo "[4/8] Installing to ${INSTALL_DIR}..."
# Stop service if running
if systemctl is-active --quiet gophish 2>/dev/null; then
  echo "  Stopping existing GoPhish service..."
  systemctl stop gophish
fi

# Remove old installation
if [ -d "${INSTALL_DIR}" ]; then
  echo "  Removing old installation..."
  rm -rf "${INSTALL_DIR}"
fi

mkdir -p "${INSTALL_DIR}"
cp -r gophish_unpacked/* "${INSTALL_DIR}/"
chown -R root:root "${INSTALL_DIR}"
chmod -R 755 "${INSTALL_DIR}"
chmod +x "${INSTALL_DIR}/gophish"
echo "  ✓ GoPhish installed"

echo
echo "[5/8] Generating SSL certificate (self-signed with SAN=${IP})..."
mkdir -p "${SSL_DIR}"
chown root:root "${SSL_DIR}"
chmod 755 "${SSL_DIR}"

# Create OpenSSL config with SAN
EXTFILE="${TMPDIR}/san.cnf"
cat > "${EXTFILE}" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = ${IP}
O = GoPhish
OU = Security Testing
C = TH

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = ${IP}
EOF

# Generate certificate
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout "${SSL_DIR}/gophish-ip.key" \
  -out "${SSL_DIR}/gophish-ip.crt" \
  -config "${EXTFILE}" 2>/dev/null

# Set permissions
chown -R ${GOPHISH_USER}:${GOPHISH_USER} "${SSL_DIR}"
chmod 640 "${SSL_DIR}/gophish-ip.key"
chmod 644 "${SSL_DIR}/gophish-ip.crt"
echo "  ✓ Certificate created at ${SSL_DIR}"

echo
echo "[6/8] Creating config.json..."
CONFIG_PATH="${INSTALL_DIR}/config.json"
cat > "${CONFIG_PATH}" <<JSON
{
  "admin_server": {
    "listen_url": "0.0.0.0:3333",
    "use_tls": true,
    "cert_path": "${SSL_DIR}/gophish-ip.crt",
    "key_path": "${SSL_DIR}/gophish-ip.key",
    "trusted_origins": [
      "https://${IP}:3333",
      "https://${IP}"
    ]
  },
  "phish_server": {
    "listen_url": "0.0.0.0:8080",
    "use_tls": false,
    "cert_path": "",
    "key_path": ""
  },
  "db_name": "sqlite3",
  "db_path": "gophish.db",
  "migrations_prefix": "db/db_",
  "contact_address": "security@example.com",
  "logging": {
    "filename": "",
    "level": "info"
  }
}
JSON

chown ${GOPHISH_USER}:${GOPHISH_USER} "${CONFIG_PATH}"
chmod 640 "${CONFIG_PATH}"
echo "  ✓ Configuration saved"

echo
echo "[7/8] Creating systemd service..."
cat > "${SERVICE_FILE}" <<'SERVICE'
[Unit]
Description=GoPhish Service
After=network.target

[Service]
Type=simple
User=gophish
Group=gophish
WorkingDirectory=/opt/gophish
ExecStart=/opt/gophish/gophish
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable gophish
echo "  ✓ Service created and enabled"

echo
echo "[8/8] Setting final permissions and starting service..."
chown -R ${GOPHISH_USER}:${GOPHISH_USER} "${INSTALL_DIR}"
chown -R ${GOPHISH_USER}:${GOPHISH_USER} "${SSL_DIR}"
chmod 640 "${SSL_DIR}/gophish-ip.key"
chmod 644 "${SSL_DIR}/gophish-ip.crt"

systemctl start gophish

# Wait a moment for service to start
sleep 2

echo
echo "========================================="
echo "  ✅ Installation Complete!"
echo "========================================="
echo
echo "Admin Panel:     https://${IP}:3333"
echo "Phishing Server: http://${IP}:8080"
echo
echo "📋 Next Steps:"
echo "1. Check service status: sudo systemctl status gophish"
echo "2. View logs: sudo journalctl -u gophish -f"
echo "3. Find initial password in logs: sudo journalctl -u gophish | grep 'Please login with'"
echo
echo "⚠️  Security Notes:"
echo "• The certificate is self-signed - browsers will show a warning (this is normal)"
echo "• Make sure to change the default password after first login"
echo "• Configure your firewall to restrict access to ports 3333 and 8080"
echo
echo "🔧 Useful Commands:"
echo "  Restart: sudo systemctl restart gophish"
echo "  Stop:    sudo systemctl stop gophish"
echo "  Logs:    sudo journalctl -u gophish -n 100"
echo
echo "========================================="

# Cleanup
rm -rf "$TMPDIR"
