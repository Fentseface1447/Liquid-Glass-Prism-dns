# Prism DNS Gateway

自托管 DNS 网关，支持智能流媒体解锁和 AI 服务路由。采用 Apple Liquid Glass 风格 UI。

[English](#english) | 中文

## 功能特性

- **智能 DNS 路由** - 根据域名规则将流量路由到不同代理节点
- **流媒体解锁检测** - 自动检测 Netflix、Disney+、HBO Max 等 20+ 服务的解锁状态
- **AI 服务支持** - OpenAI、Claude、Gemini、Copilot、Perplexity 路由
- **双栈 IPv4/IPv6** - 完整支持双协议
- **智能模式** - 根据解锁状态自动选择代理
- **实时监控** - 基于 SSE 的节点状态实时更新
- **现代 UI** - Apple Liquid Glass 设计风格，支持深色模式

## 快速安装

```bash
curl -sL https://raw.githubusercontent.com/mslxi/Liquid-Glass-Prism-dns/main/install.sh | sudo bash
```

安装完成后：
- Web 界面：`http://你的IP:8080`
- 用户名：`admin`
- 密码：查看日志 `journalctl -u prism-controller | grep password`

## 手动安装

### 下载二进制

从 [Releases](https://github.com/mslxi/Liquid-Glass-Prism-dns/releases) 下载对应平台的二进制文件。

```bash
# Linux amd64
wget https://github.com/mslxi/Liquid-Glass-Prism-dns/releases/latest/download/prism-controller-linux-amd64
chmod +x prism-controller-linux-amd64
mv prism-controller-linux-amd64 /usr/local/bin/prism-controller

# 创建环境文件
mkdir -p /opt/prism
echo "JWT_SECRET=$(openssl rand -hex 16)" > /opt/prism/.env

# 运行
cd /opt/prism && prism-controller --host 0.0.0.0 --port 8080
```

## 架构

```
┌─────────────────┐     ┌─────────────────┐
│  DNS 客户端     │────▶│    控制器       │
│  (边缘节点)     │     │  (Web + API)    │
└─────────────────┘     └─────────────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐     ┌─────────────────┐
│   代理节点      │◀────│   规则引擎      │
│  (出口节点)     │     │                 │
└─────────────────┘     └─────────────────┘
```

### 组件说明

| 组件 | 描述 |
|------|------|
| **控制器** | 中央服务器，提供 Web UI 和 API |
| **DNS 客户端** | 边缘节点，接收 DNS 查询 |
| **代理节点** | 出口节点，转发流量 |

## 配置

### 环境变量

| 变量 | 描述 | 默认值 |
|------|------|--------|
| `JWT_SECRET` | JWT 令牌密钥 | 必填 |

### 命令行参数

```bash
./prism-controller --host 0.0.0.0 --port 8080
```

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `--host` | 监听地址 | `0.0.0.0` |
| `--port` | 监听端口 | `8080` |

## 支持的服务

### AI 服务
OpenAI, Gemini, Claude, Copilot, Perplexity, Meta AI, Suno

### 视频流媒体
Netflix, Disney+, YouTube, HBO Max, Prime Video, Hulu, Apple TV+, Paramount+, Peacock, Crunchyroll, DAZN, Bilibili

### 音乐
Spotify

### 社交
TikTok

## Systemd 服务管理

```bash
# 查看状态
sudo systemctl status prism-controller

# 重启服务
sudo systemctl restart prism-controller

# 查看日志
journalctl -u prism-controller -f
```

## 许可证

MIT

---

<a name="english"></a>
# English

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
