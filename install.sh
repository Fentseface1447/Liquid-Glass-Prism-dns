#!/bin/bash
set -e

REPO="mslxi/Liquid-Glass-Prism-dns"
INSTALL_DIR="/opt/prism"
SERVICE_NAME="prism-controller"
BINARY_NAME="prism-controller"
DEFAULT_PORT=8080

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
        *) log_error "不支持的架构 / Unsupported architecture: $arch" ;;
    esac
}

detect_os() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case $os in
        linux) echo "linux" ;;
        darwin) echo "darwin" ;;
        *) log_error "不支持的系统 / Unsupported OS: $os" ;;
    esac
}

generate_secret() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行 / Please run as root (sudo)"
    fi
}

get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost"
}

check_port() {
    local port=$1
    if command -v ss &> /dev/null; then
        ss -tuln | grep -q ":${port} " && return 1
    elif command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":${port} " && return 1
    elif command -v lsof &> /dev/null; then
        lsof -i :${port} &>/dev/null && return 1
    fi
    return 0
}

ask_port() {
    local port=""
    echo ""
    echo -e "请输入监听端口 / Enter listen port [${YELLOW}${DEFAULT_PORT}${NC}]: \c"
    
    if [ -t 0 ]; then
        read port || port=""
    else
        read port < /dev/tty 2>/dev/null || port=""
    fi
    
    port=${port:-$DEFAULT_PORT}
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_warn "无效端口，使用默认 / Invalid port, using default: ${DEFAULT_PORT}"
        port=$DEFAULT_PORT
    fi
    
    if ! check_port "$port"; then
        log_error "端口 ${port} 已被占用 / Port ${port} is already in use. 请手动指定其他端口后重试。"
    fi
    
    echo "$port"
}

download_binary() {
    local os=$1
    local arch=$2
    local version=${3:-"latest"}
    
    log_info "正在下载 / Downloading Prism Controller for ${os}/${arch}..."
    
    local download_url
    if [ "$version" = "latest" ]; then
        download_url="https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}-${os}-${arch}"
    else
        download_url="https://github.com/${REPO}/releases/download/${version}/${BINARY_NAME}-${os}-${arch}"
    fi
    
    if command -v curl &> /dev/null; then
        curl -fsSL -o "${INSTALL_DIR}/${BINARY_NAME}" "$download_url" || log_error "下载失败 / Download failed"
    elif command -v wget &> /dev/null; then
        wget -q -O "${INSTALL_DIR}/${BINARY_NAME}" "$download_url" || log_error "下载失败 / Download failed"
    else
        log_error "需要 curl 或 wget / curl or wget required"
    fi
    
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    log_success "下载完成 / Binary downloaded"
}

create_env() {
    local jwt_secret=$(generate_secret)
    
    cat > "${INSTALL_DIR}/.env" << EOF
JWT_SECRET=${jwt_secret}
EOF
    
    chmod 600 "${INSTALL_DIR}/.env"
    log_success "环境配置已创建 / Environment file created"
}

create_systemd_service() {
    local port=$1
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Liquid Glass Prism Gateway Controller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${BINARY_NAME} --host 0.0.0.0 --port ${port}
Restart=always
RestartSec=5
Environment=GIN_MODE=release

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    log_success "系统服务已创建 / Systemd service created"
}

stop_service() {
    if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        systemctl stop ${SERVICE_NAME}
        log_success "服务已停止 / Service stopped"
    fi
}

show_install_info() {
    local ip=$(get_local_ip)
    local port=$1
    local password=$2
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Liquid Glass Prism Gateway 安装成功!            ${NC}"
    echo -e "${GREEN}   Installation Completed!                         ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Web UI:    ${BLUE}http://${ip}:${port}${NC}"
    echo -e "  用户名/Username:  ${YELLOW}admin${NC}"
    echo -e "  密码/Password:    ${YELLOW}${password}${NC}"
    echo ""
    echo -e "  ${RED}请保存您的密码! / Please save your password!${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
}

show_upgrade_info() {
    local ip=$(get_local_ip)
    local port=$1
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   升级完成! / Upgrade Completed!                  ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Web UI:    ${BLUE}http://${ip}:${port}${NC}"
    echo -e "  配置已保留 / Config preserved"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
}

get_current_port() {
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        grep -oP '\-\-port\s+\K[0-9]+' "/etc/systemd/system/${SERVICE_NAME}.service" 2>/dev/null || echo "$DEFAULT_PORT"
    else
        echo "$DEFAULT_PORT"
    fi
}

do_install() {
    log_info "开始全新安装... / Starting fresh installation..."
    
    check_root
    
    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        log_error "已安装，请使用升级或卸载 / Already installed. Use upgrade or uninstall first."
    fi
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    log_info "检测到 / Detected: ${os}/${arch}"
    
    local port=$(ask_port)
    log_info "将使用端口 / Using port: ${port}"
    
    mkdir -p ${INSTALL_DIR}
    cd ${INSTALL_DIR}
    
    download_binary "$os" "$arch"
    create_env
    create_systemd_service "$port"
    
    log_info "正在启动服务并等待密码... / Starting service and waiting for password..."
    systemctl start ${SERVICE_NAME}
    
    local password=""
    local timeout=30
    local count=0
    
    while [ $count -lt $timeout ]; do
        password=$(journalctl -u ${SERVICE_NAME} --no-pager 2>/dev/null | grep -oP 'password=\K[a-zA-Z0-9]+' | tail -1)
        if [ -n "$password" ]; then
            break
        fi
        
        if ! systemctl is-active --quiet ${SERVICE_NAME}; then
            log_error "服务启动失败，请检查日志 / Service failed to start. Check: journalctl -u ${SERVICE_NAME}"
        fi
        
        sleep 1
        count=$((count + 1))
    done
    
    if ! systemctl is-active --quiet ${SERVICE_NAME}; then
        log_error "服务启动失败 / Service failed to start. Check: journalctl -u ${SERVICE_NAME}"
    fi
    
    log_success "服务已启动 / Service started"
    
    if [ -z "$password" ]; then
        password="请查看日志 / Check: journalctl -u ${SERVICE_NAME} | grep password"
    fi
    
    show_install_info "$port" "$password"
}

do_upgrade() {
    log_info "开始升级... / Starting upgrade..."
    
    check_root
    
    if [ ! -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        log_error "未安装，请先安装 / Not installed. Use install first."
    fi
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    local port=$(get_current_port)
    log_info "检测到 / Detected: ${os}/${arch}"
    
    stop_service
    
    mv "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}.bak" 2>/dev/null || true
    
    download_binary "$os" "$arch"
    
    rm -f "${INSTALL_DIR}/${BINARY_NAME}.bak"
    
    systemctl start ${SERVICE_NAME}
    sleep 2
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        log_success "服务已启动 / Service started"
    else
        log_error "服务启动失败 / Service failed to start. Check: journalctl -u ${SERVICE_NAME}"
    fi
    
    show_upgrade_info "$port"
}

do_uninstall() {
    log_info "开始卸载... / Starting uninstallation..."
    
    check_root
    
    echo ""
    echo -e "${YELLOW}将删除所有数据包括数据库! / This will remove all data including database!${NC}"
    echo -e "确定要继续吗? / Are you sure? (y/N): \c"
    
    local confirm
    if [ -t 0 ]; then
        read confirm
    else
        read confirm < /dev/tty
    fi
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "已取消 / Cancelled"
        return
    fi
    
    stop_service
    
    systemctl disable ${SERVICE_NAME} >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    
    rm -rf ${INSTALL_DIR}
    
    echo ""
    log_success "卸载完成 / Uninstallation completed"
    echo ""
}

show_menu() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Liquid Glass Prism Gateway                 ║${NC}"
    echo -e "${BLUE}║       github.com/mslxi/Liquid-Glass-Prism-dns    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) 安装 / Install    - 全新安装 / Fresh installation"
    echo "  2) 升级 / Upgrade    - 升级到最新版 / Upgrade to latest"
    echo "  3) 卸载 / Uninstall  - 完全移除 / Remove completely"
    echo "  0) 退出 / Exit"
    echo ""
}

main() {
    show_menu
    
    echo -e "请选择 / Select option [0-3]: \c"
    local choice
    if [ -t 0 ]; then
        read choice
    else
        read choice < /dev/tty || { echo "Error: Cannot read input"; exit 1; }
    fi
    
    case $choice in
        1) do_install ;;
        2) do_upgrade ;;
        3) do_uninstall ;;
        0) echo "Bye!"; exit 0 ;;
        *) log_error "无效选项 / Invalid option" ;;
    esac
}

main "$@"
