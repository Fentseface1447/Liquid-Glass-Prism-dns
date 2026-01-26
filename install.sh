#!/bin/bash
set -e

REPO="mslxi/Liquid-Glass-Prism-dns"
INSTALL_DIR="/opt/prism"
SERVICE_NAME="prism-controller"
BINARY_NAME="prism-controller"
# PORT=8080 # 移除这里的硬编码，通过下面逻辑处理

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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

# --- 修改核心开始：智能获取下载地址 ---
download_binary() {
    local os=$1 arch=$2
    local asset_name="${BINARY_NAME}-${os}-${arch}"
    local api_url="https://api.github.com/repos/${REPO}/releases"
    local download_url=""

    log_info "正在查询包含 ${asset_name} 的最新可用版本..."
    
    # 获取 API 响应内容 (兼容 curl 和 wget)
    local response=""
    if command -v curl &>/dev/null; then
        response=$(curl -s "$api_url")
    elif command -v wget &>/dev/null; then
        response=$(wget -qO- "$api_url")
    else
        log_error "系统需要 curl 或 wget 才能运行"
    fi

    # 解析 JSON 查找下载地址
    # 逻辑：查找 browser_download_url 且链接结尾是 asset_name 的行
    # head -n 1 确保我们取到的是列表里最靠前（也就是最新）的那个匹配项
    download_url=$(echo "$response" | grep -oE "\"browser_download_url\": \"[^\"]+/${asset_name}\"" | head -n 1 | cut -d '"' -f 4)

    if [ -z "$download_url" ]; then
        log_error "未找到适用于 ${os}/${arch} 的发行包 (检查了最近的 Release)"
    fi

    log_info "找到版本地址: ${download_url}"
    log_info "开始下载..."

    local temp_file="/tmp/${BINARY_NAME}.tmp"

    if command -v curl &>/dev/null; then
        curl -fsSL -o "$temp_file" "$download_url" || log_error "下载失败"
    elif command -v wget &>/dev/null; then
        wget -q -O "$temp_file" "$download_url" || log_error "下载失败"
    fi

    if [ ! -s "$temp_file" ]; then
        rm -f "$temp_file"
        log_error "下载文件为空或失败"
    fi

    chmod +x "$temp_file"
    mkdir -p ${INSTALL_DIR}
    mv "$temp_file" "${INSTALL_DIR}/${BINARY_NAME}"
    log_ok "下载完成"
}
# --- 修改核心结束 ---

create_env() {
    cat > "${INSTALL_DIR}/.env" << EOF
JWT_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
GIN_MODE=release
EOF
    chmod 600 "${INSTALL_DIR}/.env"
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
    
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    log_ok "服务配置完成"
}

init_and_get_password() {
    log_info "初始化数据库并获取密码..." >&2

    cd ${INSTALL_DIR}
    
    local output=$(timeout 5 ./${BINARY_NAME} --host 127.0.0.1 --port 0 2>&1 || true)
    local password=$(echo "$output" | grep -oP 'password=\K[a-zA-Z0-9]+' | head -1)
    
    if [ -z "$password" ]; then
        password="初始化失败，请查看: journalctl -u ${SERVICE_NAME}"
    fi
    
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
    
    echo ""
    echo -n "请输入端口 [默认 8080]: "
    read -r input_port
    PORT=${input_port:-8080}
    
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        log_warn "端口无效，使用默认 8080"
        PORT=8080
    fi
    
    if ! check_port "$PORT"; then
        log_error "端口 ${PORT} 已被占用，请选择其他端口"
    fi
    
    log_info "使用端口: ${PORT}"
    
    # 传递 os 和 arch
    download_binary "$os" "$arch"
    create_env
    
    local password=$(init_and_get_password)
    
    create_service "$PORT"
    
    log_info "正在启动服务..."
    systemctl start ${SERVICE_NAME}
    sleep 2
    
    if ! systemctl is-active --quiet ${SERVICE_NAME}; then
        log_error "服务启动失败，请检查: journalctl -u ${SERVICE_NAME}"
    fi
    
    log_ok "服务已启动"
    
    local ip=$(get_local_ip)
    echo ""
    echo -e "${BLUE}[INFO]${NC} ══════════════════════════════════════════"
    echo -e "${BLUE}[INFO]${NC}     Liquid Glass Prism Gateway"
    echo -e "${BLUE}[INFO]${NC} ══════════════════════════════════════════"
    echo ""
    echo -e "  地址:   ${BLUE}http://${ip}:${PORT}${NC}"
    echo -e "  用户名: ${YELLOW}admin${NC}"
    echo -e "  密码:   ${YELLOW}${password}${NC}"
    echo ""
    echo -e "  ${RED}请保存您的密码!${NC}"
    echo ""
    echo -e "${BLUE}[INFO]${NC} ══════════════════════════════════════════"
}

backup_data() {
    local db_path="${INSTALL_DIR}/data.db"
    local backup_dir="${INSTALL_DIR}/data_bak"

    if [ -f "$db_path" ]; then
        log_info "正在备份数据库..."
        mkdir -p "$backup_dir"
        local timestamp=$(date +%Y%m%d%H%M%S)
        cp "$db_path" "${backup_dir}/data.db.${timestamp}"
        log_ok "数据库已备份至: ${backup_dir}/data.db.${timestamp}"
    fi
}

do_upgrade() {
    log_info "开始升级..."
    check_root

    [ ! -f "${INSTALL_DIR}/${BINARY_NAME}" ] && log_error "未安装，请先安装"

    local os=$(detect_os)
    local arch=$(detect_arch)
    local port=$(get_current_port)

    systemctl stop ${SERVICE_NAME} 2>/dev/null || true

    backup_data # 添加备份步骤

    mv "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}.bak" 2>/dev/null || true
    
    # 传递 os 和 arch
    download_binary "$os" "$arch"
    
    rm -f "${INSTALL_DIR}/${BINARY_NAME}.bak"

    if [ -f "${INSTALL_DIR}/.env" ] && ! grep -q "GIN_MODE" "${INSTALL_DIR}/.env"; then
        log_info "更新配置文件: 添加 GIN_MODE=release"
        echo "GIN_MODE=release" >> "${INSTALL_DIR}/.env"
    fi

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
    read -r confirm

    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "已取消"; return; }

    systemctl stop ${SERVICE_NAME} 2>/dev/null || true

    backup_data # 卸载前备份

    systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload

    # 保留备份目录，删除其他所有文件
    if [ -d "${INSTALL_DIR}" ]; then
        find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 ! -name "data_bak" -exec rm -rf {} +
    fi

    log_ok "卸载完成"
    if [ -d "${INSTALL_DIR}/data_bak" ]; then
        log_info "数据库备份已保留在: ${INSTALL_DIR}/data_bak"
    fi
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
    read -r choice
    
    case $choice in
        1) do_install ;;
        2) do_upgrade ;;
        3) do_uninstall ;;
        0) exit 0 ;;
        *) log_error "无效选项" ;;
    esac
}

main
