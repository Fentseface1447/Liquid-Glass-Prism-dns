# Liquid Glass Prism Gateway

A self-hosted DNS gateway with smart streaming unlock and AI services unlock detection. Features a beautiful Liquid Glass-inspired UI.

[中文](README.md) | English

## Features

- **Smart DNS Routing** - Route traffic through different Proxy Agents based on domain rules
- **External Ruleset Support** - Import external ruleset files for quick configuration of common services
- **Streaming Unlock Detection** - Auto-detect unlock status for Netflix, Disney+, HBO Max, and 20+ services
- **AI Services Unlock Detection** - Auto-detect availability of OpenAI, Claude, Gemini, Copilot and other AI services
- **Dual-Stack IPv4/IPv6** - Full support for both protocols
- **Smart Mode** - Automatic proxy selection based on unlock status
- **Real-time Monitoring** - SSE-based live node status updates
- **Modern UI** - Liquid Glass design with dark mode support

## Installation

```bash
curl -sL https://raw.githubusercontent.com/mslxi/Liquid-Glass-Prism-dns/main/install.sh | sudo bash
```

The script provides the following options:
- **1. Install** - Fresh installation, displays login password upon completion
- **2. Upgrade** - Upgrade to latest version, preserves configuration
- **3. Uninstall** - Complete removal with data cleanup

After installation:
- Web UI: `http://YOUR_IP:8080`
- Username: `admin`
- Password: Displayed after installation

## Manual Installation

### Download Binary

Download the binary for your platform from [Releases](https://github.com/mslxi/Liquid-Glass-Prism-dns/releases).

```bash
# Linux amd64
wget https://github.com/mslxi/Liquid-Glass-Prism-dns/releases/latest/download/prism-controller-linux-amd64
chmod +x prism-controller-linux-amd64
mv prism-controller-linux-amd64 /usr/local/bin/prism-controller

# Create environment file
mkdir -p /opt/prism
echo "JWT_SECRET=$(openssl rand -hex 16)" > /opt/prism/.env

# Run
cd /opt/prism && prism-controller --host 0.0.0.0 --port 8080
```

## Architecture

```
┌─────────────────┐
│   Controller    │  Central Controller (Web UI + API + Rule Engine)
│                 │
└────────┬────────┘
         │ Push Rules
         ▼
┌─────────────────┐     ┌─────────────────┐
│   DNS Client    │────▶│   Proxy Agent   │
│  (Edge Node)    │     │  (Exit Node)    │
│  Receive DNS    │     │  Forward Traffic│
└─────────────────┘     └─────────────────┘
```

### Components

| Component | Description |
|-----------|-------------|
| **Controller** | Central controller with Web UI, API and rule engine. Pushes rules to DNS Client |
| **DNS Client** | Edge node that receives DNS queries, forwards traffic to Proxy Agent based on rules |
| **Proxy Agent** | Exit node that receives traffic from DNS Client and forwards to target servers |

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `JWT_SECRET` | Secret key for JWT tokens | Required |

### Command Line Flags

```bash
./prism-controller --host 0.0.0.0 --port 8080
```

| Flag | Description | Default |
|------|-------------|---------|
| `--host` | Listen address | `0.0.0.0` |
| `--port` | Listen port | `8080` |

## Systemd Service

```bash
# Check status
sudo systemctl status prism-controller

# Restart service
sudo systemctl restart prism-controller

# View logs
journalctl -u prism-controller -f
```

## License

MIT
