#!/bin/bash
set -e

REPO="mslxi/Liquid-Glass-Prism-dns"
INSTALL_DIR="/opt/prism"
SERVICE_NAME="prism-controller"
BINARY_NAME="prism-controller"
PORT=8080

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[信息]${NC} $1"; }
log_ok() { echo -e "${GREEN}[完成]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
log_error() { echo -e "${RED}[错误]${NC} $1"; exit 1; }

check_root() {
    [ "$EUID" -eq 0 ] || log_error "请使用 root 权限运行 (sudo)"
}

detect_arch() {
    case $(uname -m) in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) log_error "不支持的架构: $(uname -m)" ;;
    esac
}

detect_os() {
    case $(uname -s | tr '[:upper:]' '[:lower:]') in
        linux) echo "linux" ;;
        darwin) echo "darwin" ;;
        *) log_error "不支持的系统: $(uname -s)" ;;
    esac
}

check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        ss -tuln 2>/dev/null | grep -q ":${port} " && return 1
    elif command -v netstat &>/dev/null; then
        netstat -tuln 2>/dev/null | grep -q ":${port} " && return 1
    fi
    return 0
}

get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost"
}

download_binary() {
    local os=$1 arch=$2
    local url="https://github.com/${REPO}/releases/latest/download/${BINARY_NAME}-${os}-${arch}"
    
    log_info "正在下载 ${os}/${arch} 版本..."
    
    mkdir -p ${INSTALL_DIR}
    
    if command -v curl &>/dev/null; then
        curl -fsSL -o "${INSTALL_DIR}/${BINARY_NAME}" "$url" || log_error "下载失败"
    elif command -v wget &>/dev/null; then
        wget -q -O "${INSTALL_DIR}/${BINARY_NAME}" "$url" || log_error "下载失败"
    else
        log_error "需要 curl 或 wget"
    fi
    
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    log_ok "下载完成"
}

create_service() {
    local port=$1
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Liquid Glass Prism Gateway
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
    
    cat > "${INSTALL_DIR}/.env" << EOF
JWT_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
EOF
    chmod 600 "${INSTALL_DIR}/.env"
    
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    log_ok "服务配置完成"
}

wait_for_password() {
    local password="" count=0
    
    log_info "正在启动服务..."
    systemctl start ${SERVICE_NAME}
    
    while [ $count -lt 30 ]; do
        if ! systemctl is-active --quiet ${SERVICE_NAME}; then
            log_error "服务启动失败，请检查: journalctl -u ${SERVICE_NAME}"
        fi
        
        password=$(journalctl -u ${SERVICE_NAME} --no-pager 2>/dev/null | grep -oP 'password=\K[a-zA-Z0-9]+' | tail -1)
        [ -n "$password" ] && break
        
        sleep 1
        count=$((count + 1))
    done
    
    log_ok "服务已启动"
    echo "$password"
}

get_current_port() {
    grep -oP '\-\-port\s+\K[0-9]+' "/etc/systemd/system/${SERVICE_NAME}.service" 2>/dev/null || echo "8080"
}

do_install() {
    log_info "开始安装..."
    check_root
    
    [ -f "${INSTALL_DIR}/${BINARY_NAME}" ] && log_error "已安装，请使用升级或卸载"
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    log_info "系统: ${os}/${arch}"
    
    # 询问端口
    echo ""
    echo -n "请输入端口 [默认 8080]: "
    read -r input_port 2>/dev/null || input_port=""
    PORT=${input_port:-8080}
    
    # 验证端口
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        log_warn "端口无效，使用默认 8080"
        PORT=8080
    fi
    
    # 检查端口占用
    if ! check_port "$PORT"; then
        log_error "端口 ${PORT} 已被占用，请选择其他端口"
    fi
    
    log_info "使用端口: ${PORT}"
    
    download_binary "$os" "$arch"
    create_service "$PORT"
    
    local password=$(wait_for_password)
    [ -z "$password" ] && password="请查看: journalctl -u ${SERVICE_NAME} | grep password"
    
    local ip=$(get_local_ip)
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
    echo -e "${GREEN}        安装成功!                         ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
    echo ""
    echo -e "  地址:   ${BLUE}http://${ip}:${PORT}${NC}"
    echo -e "  用户名: ${YELLOW}admin${NC}"
    echo -e "  密码:   ${YELLOW}${password}${NC}"
    echo ""
    echo -e "  ${RED}请保存您的密码!${NC}"
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════${NC}"
}

do_upgrade() {
    log_info "开始升级..."
    check_root
    
    [ ! -f "${INSTALL_DIR}/${BINARY_NAME}" ] && log_error "未安装，请先安装"
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    local port=$(get_current_port)
    
    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    
    mv "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}.bak" 2>/dev/null || true
    download_binary "$os" "$arch"
    rm -f "${INSTALL_DIR}/${BINARY_NAME}.bak"
    
    systemctl start ${SERVICE_NAME}
    sleep 2
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        log_ok "升级完成"
        echo ""
        echo -e "  地址: ${BLUE}http://$(get_local_ip):${port}${NC}"
        echo ""
    else
        log_error "服务启动失败"
    fi
}

do_uninstall() {
    log_info "开始卸载..."
    check_root
    
    echo ""
    echo -e "${YELLOW}将删除所有数据！确定吗? (y/N): ${NC}\c"
    read -r confirm 2>/dev/null || confirm=""
    
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "已取消"; return; }
    
    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    rm -rf ${INSTALL_DIR}
    
    log_ok "卸载完成"
}

show_menu() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      Liquid Glass Prism Gateway            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) 安装"
    echo "  2) 升级"
    echo "  3) 卸载"
    echo "  0) 退出"
    echo ""
}

main() {
    show_menu
    echo -n "请选择 [0-3]: "
    read -r choice 2>/dev/null || choice=""
    
    case $choice in
        1) do_install ;;
        2) do_upgrade ;;
        3) do_uninstall ;;
        0) exit 0 ;;
        *) log_error "无效选项" ;;
    esac
}

main
