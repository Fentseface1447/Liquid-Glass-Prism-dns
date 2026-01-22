#!/bin/bash
set -e

REPO="mslxi/Liquid-Glass-Prism-dns"
INSTALL_DIR="/opt/prism"
SERVICE_NAME="prism-controller"
BINARY_NAME="prism-controller"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) log_error "Unsupported architecture: $arch" ;;
    esac
}

detect_os() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case $os in
        linux) echo "linux" ;;
        darwin) echo "darwin" ;;
        *) log_error "Unsupported OS: $os" ;;
    esac
}

generate_secret() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo)"
    fi
}

download_binary() {
    local os=$1
    local arch=$2
    local version=${3:-"latest"}
    
    log_info "Downloading Prism Controller for ${os}/${arch}..."
    
    local download_url
    if [ "$version" = "latest" ]; then
        download_url="https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}-${os}-${arch}"
    else
        download_url="https://github.com/${REPO}/releases/download/${version}/${BINARY_NAME}-${os}-${arch}"
    fi
    
    if command -v curl &> /dev/null; then
        curl -fsSL -o "${INSTALL_DIR}/${BINARY_NAME}" "$download_url" || log_error "Download failed"
    elif command -v wget &> /dev/null; then
        wget -q -O "${INSTALL_DIR}/${BINARY_NAME}" "$download_url" || log_error "Download failed"
    else
        log_error "curl or wget required"
    fi
    
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    log_success "Binary downloaded"
}

create_env() {
    if [ -f "${INSTALL_DIR}/.env" ]; then
        log_warn ".env already exists, skipping"
        return
    fi
    
    local jwt_secret=$(generate_secret)
    
    cat > "${INSTALL_DIR}/.env" << EOF
JWT_SECRET=${jwt_secret}
EOF
    
    chmod 600 "${INSTALL_DIR}/.env"
    log_success "Environment file created"
}

create_systemd_service() {
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Prism DNS Gateway Controller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${BINARY_NAME} --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5
Environment=GIN_MODE=release

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    log_success "Systemd service created"
}

start_service() {
    systemctl start ${SERVICE_NAME}
    sleep 2
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        log_success "Service started"
    else
        log_error "Service failed to start. Check: journalctl -u ${SERVICE_NAME}"
    fi
}

get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost"
}

show_login_info() {
    local ip=$(get_local_ip)
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Prism Gateway Installed Successfully ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "  Web UI:    ${BLUE}http://${ip}:8080${NC}"
    echo -e "  Username:  ${YELLOW}admin${NC}"
    echo -e "  Password:  ${YELLOW}Check startup logs${NC}"
    echo ""
    echo -e "  Get password: ${BLUE}journalctl -u ${SERVICE_NAME} | grep password${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Prism DNS Gateway Installer         ║${NC}"
    echo -e "${BLUE}║   github.com/${REPO}  ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
    echo ""
    
    check_root
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    log_info "Detected: ${os}/${arch}"
    
    mkdir -p ${INSTALL_DIR}
    cd ${INSTALL_DIR}
    
    download_binary "$os" "$arch"
    create_env
    create_systemd_service
    start_service
    show_login_info
}

main "$@"
