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

get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost"
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
Description=Liquid Glass Prism Gateway Controller
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
    systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    log_success "Systemd service created"
}

start_service() {
    systemctl start ${SERVICE_NAME}
    sleep 3
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        log_success "Service started"
    else
        log_error "Service failed to start. Check: journalctl -u ${SERVICE_NAME}"
    fi
}

stop_service() {
    if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        systemctl stop ${SERVICE_NAME}
        log_success "Service stopped"
    fi
}

show_install_info() {
    local ip=$(get_local_ip)
    local password=$1
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Liquid Glass Prism Gateway Installed!       ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Web UI:    ${BLUE}http://${ip}:8080${NC}"
    echo -e "  Username:  ${YELLOW}admin${NC}"
    echo -e "  Password:  ${YELLOW}${password}${NC}"
    echo ""
    echo -e "  ${RED}Please save your password!${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
}

show_upgrade_info() {
    local ip=$(get_local_ip)
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Upgrade Completed!                          ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Web UI:    ${BLUE}http://${ip}:8080${NC}"
    echo -e "  Config:    Preserved"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
}

do_install() {
    log_info "Starting fresh installation..."
    
    check_root
    
    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        log_error "Already installed. Use upgrade or uninstall first."
    fi
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    log_info "Detected: ${os}/${arch}"
    
    mkdir -p ${INSTALL_DIR}
    cd ${INSTALL_DIR}
    
    download_binary "$os" "$arch"
    create_env
    create_systemd_service
    start_service
    
    sleep 2
    local password=$(journalctl -u ${SERVICE_NAME} --no-pager 2>/dev/null | grep -oP 'password=\K[a-zA-Z0-9]+' | tail -1)
    if [ -z "$password" ]; then
        password="Check: journalctl -u ${SERVICE_NAME} | grep password"
    fi
    
    show_install_info "$password"
}

do_upgrade() {
    log_info "Starting upgrade..."
    
    check_root
    
    if [ ! -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        log_error "Not installed. Use install first."
    fi
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    log_info "Detected: ${os}/${arch}"
    
    stop_service
    
    mv "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}.bak" 2>/dev/null || true
    
    download_binary "$os" "$arch"
    
    rm -f "${INSTALL_DIR}/${BINARY_NAME}.bak"
    
    start_service
    show_upgrade_info
}

do_uninstall() {
    log_info "Starting uninstallation..."
    
    check_root
    
    echo ""
    echo -e "${YELLOW}This will remove all data including database!${NC}"
    read -p "Are you sure? (y/N): " confirm < /dev/tty
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled"
        return
    fi
    
    stop_service
    
    systemctl disable ${SERVICE_NAME} >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    
    rm -rf ${INSTALL_DIR}
    
    echo ""
    log_success "Uninstallation completed"
    echo ""
}

show_menu() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Liquid Glass Prism Gateway                 ║${NC}"
    echo -e "${BLUE}║       github.com/mslxi/Liquid-Glass-Prism-dns    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) Install    - Fresh installation"
    echo "  2) Upgrade    - Upgrade to latest version"
    echo "  3) Uninstall  - Remove completely"
    echo "  0) Exit"
    echo ""
}

main() {
    show_menu
    
    if [ -t 0 ]; then
        read -p "Select option [0-3]: " choice
    else
        read -p "Select option [0-3]: " choice < /dev/tty || { echo "Error: Cannot read input. Run with: bash -s"; exit 1; }
    fi
    
    case $choice in
        1) do_install ;;
        2) do_upgrade ;;
        3) do_uninstall ;;
        0) echo "Bye!"; exit 0 ;;
        *) log_error "Invalid option" ;;
    esac
}

main "$@"
