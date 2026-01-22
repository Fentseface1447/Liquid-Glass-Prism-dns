#!/bin/bash

set -e

REPO="mslxi/Liquid-Glass-Prism-dns"
BINARY_NAME="prism-agent"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="prism-agent"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/main/agent_install.sh"
CUSTOM_IP=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[STEP]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root (sudo)"
    fi
}

parse_args() {
    MASTER_ADDR=""
    SECRET_TOKEN=""
    UNINSTALL_MODE=false
    BETA_MODE=false
    SMART_MODE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --master)
                if [ -n "$2" ] && [ "${2:0:2}" != "--" ]; then
                    MASTER_ADDR="$2"
                    shift 2
                else
                    error "--master requires a value"
                fi
                ;;
            --secret)
                if [ -n "$2" ] && [ "${2:0:2}" != "--" ]; then
                    SECRET_TOKEN="$2"
                    shift 2
                else
                    error "--secret requires a value"
                fi
                ;;
            --name)
                if [ -n "$2" ] && [ "${2:0:2}" != "--" ]; then
                    SERVICE_NAME="$2"
                    shift 2
                else
                    shift 1
                fi
                ;;
            --ip)
                if [ -n "$2" ] && [ "${2:0:2}" != "--" ]; then
                    CUSTOM_IP="$2"
                    shift 2
                else
                    shift 1
                fi
                ;;
            --uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            --beta)
                BETA_MODE=true
                shift
                ;;
            --smart)
                SMART_MODE=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ "$UNINSTALL_MODE" = true ]; then
        return
    fi

    if [ -z "$MASTER_ADDR" ] || [ -z "$SECRET_TOKEN" ]; then
        echo -e "${YELLOW}Missing parameters!${NC}"
        echo -e "Usage: ... | bash -s -- --master URL --secret TOKEN [--beta] [--smart]"
        exit 1
    fi
}

uninstall_agent() {
    step "Uninstalling Prism Agent ($SERVICE_NAME)..."
    
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        rm "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi
    
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        rm "$INSTALL_DIR/$BINARY_NAME"
    fi
    
    info "Uninstallation completed."
    exit 0
}

detect_system() {
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$ARCH" in
        x86_64) ARCH_SUFFIX="amd64" ;;
        aarch64|arm64) ARCH_SUFFIX="arm64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    ASSET_NAME="${BINARY_NAME}_${OS}_${ARCH_SUFFIX}"
    info "Detected: ${OS} / ${ARCH_SUFFIX}"
}

download_binary() {
    step "Fetching version info..."

    if [ "$BETA_MODE" = true ]; then
        API_URL="https://api.github.com/repos/$REPO/releases"
        info "Mode: ${YELLOW}Beta Channel (Pre-release)${NC}"
    else
        API_URL="https://api.github.com/repos/$REPO/releases/latest"
        info "Mode: ${GREEN}Stable Channel (Official)${NC}"
    fi
    
    RESP=$(curl -s --connect-timeout 5 "$API_URL")

    if [ "$BETA_MODE" = true ]; then
        VERSION=$(echo "$RESP" | grep '"tag_name":' | grep -i "beta" | head -n 1 | cut -d '"' -f 4)
        if [ -z "$VERSION" ]; then
            warn "No Beta version found, trying latest..."
            VERSION=$(echo "$RESP" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
        fi
    else
        VERSION=$(echo "$RESP" | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4)
    fi

    if [ -n "$VERSION" ]; then
        info "Found version: ${CYAN}${VERSION}${NC}"
        DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET_NAME"
    else
        warn "Cannot get version info via API, using generic link..."
        DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
    fi

    info "Download URL: $DOWNLOAD_URL"
    curl -L -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" --progress-bar

    if [ ! -f "/tmp/$BINARY_NAME" ]; then
        error "Download failed. Please check network or GitHub access."
    fi

    chmod +x "/tmp/$BINARY_NAME"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "Stopping old service..."
        systemctl stop "$SERVICE_NAME"
    fi

    mv "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
}

configure_service() {
    step "Configuring systemd service..."
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    EXEC_ARGS="--master \"$MASTER_ADDR\" --secret \"$SECRET_TOKEN\""
    
    if [ "$SMART_MODE" = true ]; then
        EXEC_ARGS="$EXEC_ARGS --smart"
    fi

    if [ -n "$CUSTOM_IP" ]; then
        EXEC_ARGS="$EXEC_ARGS --ip \"$CUSTOM_IP\""
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Liquid Glass Prism Agent ($SERVICE_NAME)
After=network.target

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
ExecStart=$INSTALL_DIR/$BINARY_NAME $EXEC_ARGS
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
}

start_service() {
    step "Starting service..."
    systemctl restart "$SERVICE_NAME"
    
    info "Waiting for initialization..."
    sleep 3

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        error "Failed to start! Check logs: journalctl -u $SERVICE_NAME -n 20"
    fi
}

show_result() {
    LOGS=$(journalctl -u "$SERVICE_NAME" -n 50 --no-pager)
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Liquid Glass Prism Agent Installed!         ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    
    if [ "$BETA_MODE" = true ]; then
        echo -e "  Version: ${YELLOW}Beta (Pre-release)${NC}"
    fi
    
    if [ "$SMART_MODE" = true ]; then
        echo -e "  Feature: ${CYAN}Smart Mode Enabled${NC}"
    fi

    if echo "$LOGS" | grep -q "DNS Mode Started"; then
        echo -e "  Mode:    ${CYAN}DNS Client${NC} (Set DNS to 127.0.0.1)"
    elif echo "$LOGS" | grep -q "Proxy Mode Started"; then
        echo -e "  Mode:    ${CYAN}Proxy Agent${NC} (Open ports 80/443)"
    else
        warn "  Syncing config, check logs shortly."
    fi
    
    echo ""
    echo -e "  Uninstall: ${GREEN}curl -sL $SCRIPT_URL | bash -s -- --uninstall${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
}

show_banner() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Liquid Glass Prism Agent Installer         ║${NC}"
    echo -e "${BLUE}║       github.com/mslxi/Liquid-Glass-Prism-dns    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    show_banner
    check_root
    parse_args "$@"
    
    if [ "$UNINSTALL_MODE" = true ]; then
        uninstall_agent
    fi

    detect_system
    download_binary
    configure_service
    start_service
    show_result
}

main "$@"
