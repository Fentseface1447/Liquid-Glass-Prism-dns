# Prism DNS Gateway

A self-hosted DNS gateway with smart streaming unlock and AI services routing. Features a beautiful Apple Liquid Glass-inspired UI.

## Features

- **Smart DNS Routing** - Route traffic through different proxy nodes based on domain rules
- **Streaming Unlock Detection** - Auto-detect unlock status for Netflix, Disney+, HBO Max, and 20+ services
- **AI Services Support** - OpenAI, Claude, Gemini, Copilot, Perplexity routing
- **Dual-Stack IPv4/IPv6** - Full support for both protocols
- **Smart Mode** - Automatic proxy selection based on unlock status
- **Real-time Monitoring** - SSE-based live node status updates
- **Modern UI** - Apple Liquid Glass design with dark mode support

## Quick Install

```bash
curl -sL https://raw.githubusercontent.com/mslxi/Liquid-Glass-Prism-dns/main/install.sh | sudo bash
```

After installation:
- Web UI: `http://YOUR_IP:8080`
- Username: `admin`
- Password: Check logs with `journalctl -u prism-controller | grep password`

## Manual Installation

### Prerequisites

- Go 1.24+
- Node.js 18+

### Build from Source

```bash
git clone https://github.com/mslxi/Liquid-Glass-Prism-dns.git
cd Liquid-Glass-Prism-dns

# Build frontend
cd web && npm install && npm run build -- --outDir ../cmd/controller/dist && cd ..

# Build backend
go build -o prism-controller cmd/controller/main.go

# Create environment file
echo "JWT_SECRET=$(openssl rand -hex 16)" > .env

# Run
./prism-controller --host 0.0.0.0 --port 8080
```

## Architecture

```
┌─────────────────┐     ┌─────────────────┐
│  DNS Client     │────▶│   Controller    │
│  (Edge Node)    │     │  (Web + API)    │
└─────────────────┘     └─────────────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐     ┌─────────────────┐
│  Proxy Agent    │◀────│   Rule Engine   │
│  (Exit Node)    │     │                 │
└─────────────────┘     └─────────────────┘
```

### Components

| Component | Description |
|-----------|-------------|
| **Controller** | Central server with web UI and API |
| **DNS Client** | Edge node that receives DNS queries |
| **Proxy Agent** | Exit node that forwards traffic |

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

## Supported Services

### AI Services
OpenAI, Gemini, Claude, Copilot, Perplexity, Meta AI, Suno

### Video Streaming
Netflix, Disney+, YouTube, HBO Max, Prime Video, Hulu, Apple TV+, Paramount+, Peacock, Crunchyroll, DAZN, Bilibili

### Music
Spotify

### Social
TikTok

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/login` | User authentication |
| GET | `/api/nodes` | List all nodes |
| POST | `/api/nodes` | Create new node |
| GET | `/api/rules` | List routing rules |
| POST | `/api/rules` | Create/update rule |
| GET | `/api/sse` | Server-sent events stream |

## Docker

```bash
docker build -t prism-controller .
docker run -d -p 8080:8080 -v $(pwd)/.env:/app/.env prism-controller
```

## License

MIT
