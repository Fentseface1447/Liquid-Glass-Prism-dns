# Liquid Glass Prism Gateway

自托管 DNS 网关，支持智能流媒体解锁和 AI 服务路由。采用 Liquid Glass 风格 UI。

[English](README_EN.md) | 中文

## 功能特性

- **智能 DNS 路由** - 根据域名规则将流量路由到不同 Proxy Agent
- **外部规则集支持** - 支持导入外部规则集文件，快速配置常用服务
- **流媒体解锁检测** - 自动检测 Netflix、Disney+、HBO Max 等 20+ 服务的解锁状态
- **AI 服务支持** - OpenAI、Claude、Gemini、Copilot、Perplexity 路由
- **双栈 IPv4/IPv6** - 完整支持双协议
- **智能模式** - 根据解锁状态自动选择代理
- **实时监控** - 基于 SSE 的节点状态实时更新
- **现代 UI** - Liquid Glass 设计风格，支持深色模式

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
┌─────────────────┐
│   Controller    │  中央控制器 (Web UI + API + 规则引擎)
│                 │
└────────┬────────┘
         │ 下发规则
         ▼
┌─────────────────┐     ┌─────────────────┐
│   DNS Client    │────▶│   Proxy Agent   │
│   (边缘节点)    │     │   (出口节点)    │
│  接收DNS查询    │     │   转发流量      │
└─────────────────┘     └─────────────────┘
```

### 组件说明

| 组件 | 描述 |
|------|------|
| **Controller** | 中央控制器，提供 Web UI、API 和规则引擎，向 DNS Client 下发规则 |
| **DNS Client** | 边缘节点，接收 DNS 查询，根据规则将流量转发到对应 Proxy Agent |
| **Proxy Agent** | 出口节点，接收来自 DNS Client 的流量并转发到目标服务器 |

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
