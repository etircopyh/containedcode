# ContainedCode — Universal Coding Agent Container

<p align="center">
  <strong>Run any AI coding agent (Pi, Codex CLI, Amp, etc.) in a secure, pre-configured container with SSH access and an optional web IDE server.</strong>
</p>

<p align="center">
  <a href="https://github.com/etircopyh/containedcode/actions/workflows/ci.yml"><img src="https://github.com/etircopyh/containedcode/workflows/CI/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/platforms-linux%2Famd64%2C%20linux%2Farm64-blue" alt="Multi-platform">
</p>

---

## What is ContainedCode?

A batteries-included Docker container that gives you:

- **Multiple AI coding agents** — Pi, Codex CLI, and Amp pre-installed. Switch with `AGENT_CMD=codex`.
- **Web IDE server** — optional OpenCode server for browser-based editing.
- **SSH access** — connect from anywhere, attach to the tmux session, and work remotely.
- **80,000+ packages** via Nix — install anything on the fly.
- **Pre-installed tools** — git, Node.js, Python, Go, Rust, PostgreSQL client, Redis CLI, and more.
- **Persistent workspace** — your code and config survive container restarts.
- **Language servers** — TypeScript, Python, Go, Rust, Lua, YAML, Bash, Dockerfile, HTML/CSS/JSON.

---

## Quick Start

```bash
# 1. Set your password and choose an agent
cp .env.example .env
# Edit .env: set WEB_SERVER_PASSWORD=your-password

# 2. Start the container
./start.sh

# 3. Attach to the agent
./start.sh --attach
```

To also start the web IDE server (requires a password):

```bash
WEB_SERVER_PASSWORD=secret ./start.sh --web
```

Connect from an OpenCode client:

```bash
opencode attach http://localhost:8888
# Username: opencode
# Password: your-password
```

---

## Pre-built Images

Multi-platform images (linux/amd64, linux/arm64) are published to GitHub Container Registry:

```bash
docker pull ghcr.io/etircopyh/containedcode:latest
```

| Tag | Description |
|-----|-------------|
| `latest` | Latest release |
| `v1.2.3` | Specific version |
| `main` | Latest commit on main branch |

---

## Available Agents

| Agent | AGENT_CMD | Status | Notes |
|-------|-----------|--------|-------|
| Pi | `pi` (default) | ✅ Works | v0.79.6 |
| Codex CLI | `codex` | ✅ Works | v0.140.0 |
| Amp | `amp` | ⚠️ Binary on disk | Requires glibc (not Alpine's musl) |

Switch agents by setting `AGENT_CMD` in `.env`:

```bash
# .env
AGENT_CMD=codex
AGENT_ARGS=
WEB_SERVER_PASSWORD=your-password
```

---

## Usage

### Starting the Server

```bash
# Default (agent in tmux + SSH, detached)
./start.sh

# With web IDE server
./start.sh --web

# In foreground
./start.sh --foreground

# With a specific agent
AGENT_CMD=codex ./start.sh
```

### Stopping

```bash
./start.sh --stop
```

### Interactive Shell

```bash
./start.sh --shell
```

### Force Rebuild

```bash
./start.sh --build
```

### Attaching to the Agent

```bash
# Locally
./start.sh --attach

# Via SSH
ssh -p 2222 opencode@localhost
tmux attach -t agent

# Via docker exec
docker exec -it containedcode tmux attach
```

Detach from tmux: `Ctrl+b` then `d`

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_CMD` | `pi` | Agent command (pi, codex, amp, etc.) |
| `AGENT_ARGS` | — | Extra arguments for the agent |
| `WEB_SERVER_PASSWORD` | — | Web IDE password (enables the server) |
| `WEB_SERVER_ENABLED` | `auto` | Force enable/disable web server |
| `PORT` | `8888` | Web server port |
| `SSH_PORT` | `2222` | SSH host port |
| `AGENT_CONFIG_DIR` | `~/.pi` | Agent config directory |
| `WEB_CONFIG_DIR` | `~/.config/opencode` | Web IDE config directory |
| `SSH_AUTHORIZED_KEYS` | `~/.ssh/authorized_keys` | SSH public keys file |
| `AUTO_UPDATE` | `true` | Auto-update opencode on start |

Legacy `OPENCODE_SERVER_*` and `PI_*` variables are also supported.

### `.env` File

Copy `.env.example` to `.env` and configure:

```bash
# Minimal setup for remote access
WEB_SERVER_PASSWORD=your-password
SSH_AUTHORIZED_KEYS=~/.ssh/authorized_keys
```

### Web IDE Config

The web IDE (OpenCode) expects a config file at `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-5"
}
```

A minimal config is auto-created if missing.

---

## Project Management

### Adding Projects

```bash
# Copy a project into workspace (isolated copy)
./project.sh copy ~/projects/my-app

# Mount a project (live sync)
./project.sh mount ~/projects/my-app
./project.sh apply   # Generate docker-compose.override.yml
```

### Managing Projects

```bash
./project.sh list                # List all projects
./project.sh create new-project  # Create new project
./project.sh shell my-app        # Open shell in project
./project.sh remove my-app       # Remove project
```

---

## Pre-installed Tools

| Category | Tools |
|----------|-------|
| **Languages** | Node.js 22, Python 3.12, Go 1.24, Rust, Bun |
| **Databases** | PostgreSQL client, Redis CLI, MongoDB tools, SQLite |
| **Build** | Make, CMake, GCC, pkg-config |
| **Version Control** | Git, GitHub CLI |
| **Network** | curl, wget, jq, yq |
| **Editors** | nano, vim |
| **System** | htop, tmux, procps, coreutils |
| **Package Manager** | Nix (80,000+ packages), bun (Node.js), uv (Python) |
| **LSP Servers** | TypeScript, Pyright, gopls, rust-analyzer, lua-language-server, nixd, yaml-language-server, bash-language-server, dockerfile-language-server-nodejs, biome, vscode-langservers-extracted |

---

## SSH Remote Access

1. Add your public key to `~/.ssh/authorized_keys` on the **host**:

   ```bash
   echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys
   ```

2. Connect from another machine:

   ```bash
   ssh -p 2222 opencode@your-server-ip
   ```

3. Attach to the agent:

   ```bash
   tmux attach -t agent
   ```

---

## Installing Additional Packages

Inside the container (or via the agent), install any of 80,000+ Nix packages:

```bash
nix profile install nixpkgs#ripgrep
nix profile install nixpkgs#terraform
nix profile install nixpkgs#awscli2
```

Or use bun for Node.js tools:

```bash
bun install -g <package>
```

---

## Architecture

```
Container (containedcode)
├── tmux session "agent"
│   └── Agent process (pi, codex, amp, ...)
├── SSH daemon (port 2222)
├── Web IDE server (port 8888, optional)
├── Nix package manager
└── Pre-installed dev tools
```

All processes run as non-root user `opencode` (UID 1000). The container persists Nix packages, tool caches, and agent data across restarts via named Docker volumes.

---

## Security

- **No host access** — only the workspace directory is mounted.
- **Read-only config** — `opencode.json` is mounted read-only.
- **Non-root user** — all processes run as UID 1000.
- **Password required** — web IDE requires authentication.
- **Key-based SSH only** — no password authentication.
- **No new privileges** — container cannot gain additional capabilities.

---

## Building from Source

```bash
# Using Docker compose (Alpine-based)
docker compose build

# Using Nix
nix build .#default
docker load < result
```

---

## License

MIT License — See [LICENSE](LICENSE) for details.
