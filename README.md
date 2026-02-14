# OpenCode Server - Secure Container

<p align="center">
  <strong>Production-ready Docker container for OpenCode server with complete isolation</strong>
</p>

<p align="center">
  <a href="https://github.com/etircopyh/containedcode/actions/workflows/ci.yml"><img src="https://github.com/etircopyh/containedcode/workflows/CI/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/platforms-linux%2Famd64%2C%20linux%2Farm64-blue" alt="Multi-platform">
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#usage">Usage</a> •
  <a href="#project-management">Project Management</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#security">Security</a>
</p>

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Usage](#usage)
  - [Starting the Server](#starting-the-server)
  - [Stopping the Server](#stopping-the-server)
  - [Interactive Shell](#interactive-shell)
  - [Force Rebuild](#force-rebuild)
- [Project Management](#project-management)
  - [Adding Projects](#adding-projects)
  - [Managing Projects](#managing-projects)
  - [Switching Projects in Web UI](#switching-projects-in-web-ui)
  - [Directory Structure](#directory-structure)
- [Configuration](#configuration)
  - [OpenCode Config Directory](#opencode-config-directory)
  - [Environment Variables](#environment-variables)
- [Project Structure](#project-structure)
- [Security](#security)
- [Installing Additional Packages](#installing-additional-packages)
- [Pre-installed Tools](#pre-installed-tools)
- [Connecting Remotely](#connecting-remotely)
- [Troubleshooting](#troubleshooting)
- [Building from Source](#building-from-source)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Features

| Feature | Description |
|---------|-------------|
| **Complete Isolation** | No access to host `$HOME`, only mounted workspace |
| **Password Protected** | Server requires authentication via `OPENCODE_SERVER_PASSWORD` |
| **Pre-installed Tools** | git, node, python, go, rust, postgresql, redis, mongodb, and more |
| **Unlimited Autonomy** | Nix package manager with 60,000+ packages for on-demand installation |
| **Non-root User** | Runs as UID 1000 for security best practices |
| **Configurable Port** | Change via `PORT` environment variable |
| **Read-only Config** | Your `opencode.json` with API keys is mounted read-only |

---

## Quick Start

### Option 1: Use Pre-built Image (Recommended)

Pull the image from GitHub Container Registry:

```bash
# Pull latest (auto-selects your architecture)
docker pull ghcr.io/etircopyh/containedcode:latest

# Run directly
docker run -it --rm \
  -p 8888:8888 \
  -v $(pwd)/workspace:/workspace \
  -v ~/.config/opencode:/home/opencode/.config/opencode:ro \
  -e OPENCODE_SERVER_PASSWORD=your-secret-password \
  ghcr.io/etircopyh/containedcode:latest
```

### Option 2: Build Locally

```bash
# 1. Start the server (will prompt for password if not set)
OPENCODE_SERVER_PASSWORD=your-secret-password ./start.sh

# 2. Connect from any OpenCode client
opencode attach http://localhost:8888
# Username: opencode
# Password: your-secret-password
```

---

## Available Images

Pre-built multi-platform images are published to [GitHub Container Registry](https://github.com/etircopyh/containedcode/pkgs/container/containedcode):

| Tag | Description |
|-----|-------------|
| `latest` | Latest release (recommended) |
| `v1.2.3` | Specific version |
| `main` | Latest commit on main branch |
| `sha-abc123` | Specific commit |

All images support `linux/amd64` and `linux/arm64`.

---

## Requirements

| Requirement | Status | Notes |
|-------------|--------|-------|
| Docker | **Required** | Essential for containerization |
| Nix with flakes | Optional | For building from source |

---

## Usage

### Starting the Server

```bash
# Basic start (foreground)
OPENCODE_SERVER_PASSWORD=secret ./start.sh

# Run in background
OPENCODE_SERVER_PASSWORD=secret ./start.sh --detach

# Run with logs
OPENCODE_SERVER_PASSWORD=secret ./start.sh --logs

# Custom port
PORT=9999 OPENCODE_SERVER_PASSWORD=secret ./start.sh

# Generate random password
OPENCODE_SERVER_PASSWORD=$(openssl rand -base64 32) ./start.sh
```

### Stopping the Server

```bash
./start.sh --stop
```

### Interactive Shell (Debugging)

```bash
./start.sh --shell
```

### Force Rebuild

```bash
./start.sh --build
```

---

## Project Management

> **Note:** The workspace uses **project subdirectories** — one server, multiple projects accessible inside.

### Adding Projects

#### Option 1: Copy project into workspace (isolated copy)

```bash
./project.sh copy ~/projects/my-app
```

#### Option 2: Mount external project (live sync with original)

```bash
./project.sh mount ~/projects/my-app
./project.sh apply    # Generates docker-compose.override.yml
# Restart server to apply
```

### Managing Projects

```bash
# List all projects
./project.sh list

# Create new project directory
./project.sh create new-project

# Remove project from workspace
./project.sh remove my-app

# Open shell in specific project
./project.sh shell my-app
```

### Using Without Cloning the Repository

If you don't want to clone the repo, you can use the pre-built image directly with Docker:

```bash
# Create a workspace directory
mkdir -p ~/opencode-workspace
cd ~/opencode-workspace

# Run the container directly
docker run -it --rm \
  -p 8888:8888 \
  -v $(pwd):/workspace \
  -v ~/.config/opencode:/home/opencode/.config/opencode:ro \
  -e OPENCODE_SERVER_PASSWORD=your-secret-password \
  ghcr.io/etircopyh/containedcode:latest

# Or run with shell access
docker run -it --rm \
  -v $(pwd):/workspace \
  -v ~/.config/opencode:/home/opencode/.config/opencode:ro \
  ghcr.io/etircopyh/containedcode:latest /bin/shell-entrypoint
```

**Mounting external projects directly:**

```bash
# Mount your existing project without copying
docker run -it --rm \
  -p 8888:8888 \
  -v /path/to/your/project:/workspace/my-project \
  -v ~/.config/opencode:/home/opencode/.config/opencode:ro \
  -e OPENCODE_SERVER_PASSWORD=your-secret-password \
  ghcr.io/etircopyh/containedcode:latest
```

**Multiple projects:**

```bash
# Mount multiple projects into the workspace
docker run -it --rm \
  -p 8888:8888 \
  -v /path/to/project-a:/workspace/project-a \
  -v /path/to/project-b:/workspace/project-b \
  -v ~/.config/opencode:/home/opencode/.config/opencode:ro \
  -e OPENCODE_SERVER_PASSWORD=your-secret-password \
  ghcr.io/etircopyh/containedcode:latest
```

### Switching Projects in Web UI

**Important:** The OpenCode Web UI is different from the Desktop app:

| Feature | Desktop App | Web UI |
|---------|-------------|--------|
| Directory Picker | Native file picker | Entire `/workspace` treated as one project |

**When using the web interface:**

1. All mounted projects are subdirectories of `/workspace`
2. Tell the AI to navigate: `cd /workspace/my-project`
3. All your projects are accessible within this single workspace

**Example:**
```
You: cd to /workspace/langgraph_telegram_aibot and show me the src folder
AI: [navigates and shows files]
```

### Directory Structure

```
workspace/
├── my-app/          # Copied or created project
└── backend-api/     # Another project
```

**Mount vs Copy:**

| Method | Sync | Requires Restart |
|--------|------|------------------|
| **Mount** | Live sync with original | Yes |
| **Copy** | Isolated, no external changes | No |

---

## Configuration

### OpenCode Config Directory

Your entire `~/.config/opencode/` directory is mounted read-only into the container:

- `opencode.json` — Main config with API keys and providers
- `oh-my-opencode.json` — Plugin configuration
- Any other config files

To use a different config directory:

```bash
OPENCODE_CONFIG_DIR=/path/to/opencode-config OPENCODE_SERVER_PASSWORD=secret ./start.sh
```

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENCODE_SERVER_PASSWORD` | ✅ Yes | — | Password for server authentication |
| `PORT` | ❌ No | `8888` | Server port |
| `OPENCODE_CONFIG_DIR` | ❌ No | `~/.config/opencode` | Path to config directory |

---

## Project Structure

```
.
├── flake.nix           # Nix container definition
├── docker-compose.yml  # Docker Compose configuration
├── start.sh            # Launcher script
├── project.sh          # Project management helper
├── README.md           # This file
└── workspace/          # Your project files go here
```

---

## Security

### What's Protected

| Protection | Details |
|------------|---------|
| **No Host Access** | Container has no access to your `$HOME` directory |
| **Read-only Config** | `opencode.json` is mounted read-only |
| **Non-root User** | All processes run as UID 1000 |
| **Password Required** | Server rejects connections without valid credentials |
| **No New Privileges** | Container cannot gain additional capabilities |

### What to Be Aware Of

- **Workspace Access:** The container has full read/write access to `./workspace`
- **Network:** Server binds to `127.0.0.1` by default (local access only)
- **Nix Store:** Installed packages persist in a Docker volume

---

## Installing Additional Packages

Inside the container, install any package from Nixpkgs:

```bash
# Enter shell
./start.sh --shell

# Install packages
nix profile add nixpkgs#terraform
nix profile add nixpkgs#awscli2
nix profile add nixpkgs#docker-compose

# Use them
terraform --version
```

### Common Packages

```bash
# Cloud tools
nix profile add nixpkgs#terraform
nix profile add nixpkgs#ansible

# Languages
nix profile add nixpkgs#elixir
nix profile add nixpkgs#zig

# Utilities
nix profile add nixpkgs#ripgrep
nix profile add nixpkgs#fd
nix profile add nixpkgs#bat

# Additional LSP servers (if needed)
nix profile add nixpkgs#yaml-language-server
nix profile add nixpkgs#bash-language-server
nix profile add nixpkgs#dockerfile-language-server-nodejs
```

---

## Language Server Protocol (LSP) Support

OpenCode uses LSP servers for intelligent code features (diagnostics, go-to-definition, etc.). The following LSP servers are pre-installed:

| Language | Server | Command |
|----------|--------|---------|
| TypeScript/JavaScript | typescript-language-server | `typescript-language-server` |
| TypeScript/JavaScript/JSON | biome | `biome` |
| HTML/CSS/JSON/ESLint | vscode-langservers-extracted | `vscode-html-language-server`, `vscode-css-language-server`, `vscode-json-language-server`, `vscode-eslint-language-server` |
| YAML | yaml-language-server | `yaml-language-server` |
| Bash | bash-language-server | `bash-language-server` |
| Dockerfile | dockerfile-language-server-nodejs | `dockerfile-language-server-nodejs` |
| Python | pyright | `pyright` |
| Go | gopls | `gopls` |
| Rust | rust-analyzer | `rust-analyzer` |
| Lua | lua-language-server | `lua-language-server` |
| Nix | nixd | `nixd` |

### Installing Additional LSP Servers

**Inside the container**, you can install more LSP servers:

```bash
# Using Nix (recommended)
nix profile add nixpkgs#ansible-language-server
nix profile add nixpkgs#terraform-ls
nix profile add nixpkgs#clang-tools  # C/C++ language server
nix profile add nixpkgs#texlab       # LaTeX language server
nix profile add nixpkgs#marksman     # Markdown language server

# Using npm (for Node.js-based servers)
npm install -g @ansible/ansible-language-server
npm install -g @prisma/language-server
```

### Can OpenCode Install Packages Automatically?

**Not automatically**, but you can ask it to. OpenCode can run installation commands for you:

```
You: Install the YAML language server
AI: I'll install it for you using Nix...
     [runs nix profile add nixpkgs#yaml-language-server]
```

The container comes with **Nix** and **npm** available, so OpenCode can install packages when you ask it to. This is the "autonomy" feature — the AI has package managers available and can use them.

---

## Pre-installed Tools

| Category | Tools |
|----------|-------|
| **Languages** | Node.js 22, Python 3.12, Go 1.23, Rust, Bun |
| **Databases** | PostgreSQL client, Redis CLI, MongoDB tools, SQLite |
| **Build** | Make, CMake, GCC, pkg-config |
| **Version Control** | Git, GitHub CLI |
| **Network** | curl, wget, jq, yq |
| **Editors** | nano, vim |
| **System** | htop, procps, coreutils |
| **LSP Servers** | typescript-language-server, vscode-langservers-extracted (HTML/CSS/JSON/ESLint), pyright, gopls, rust-analyzer, lua-language-server, nixd, yaml-language-server, bash-language-server, dockerfile-language-server-nodejs, biome |

---

## Connecting Remotely

### From Another Machine

#### Option 1: SSH Tunnel (Recommended)

```bash
ssh -L 8888:localhost:8888 user@server
opencode attach http://localhost:8888
```

#### Option 2: Direct Access

Edit `docker-compose.yml` and change `HOSTNAME` to `0.0.0.0`, then ensure firewall allows access.

### FAQ: Can Remote OpenCode Edit Local Files?

**No.** When you connect to a remote OpenCode server:

- You can ONLY edit files on that server
- The server CANNOT access your local files
- To work on local files, mount them into the container

This is a security feature — your local machine stays isolated.

---

## Troubleshooting

### Port Already in Use

```bash
# Check what's using the port
lsof -i :8888

# Use a different port
PORT=9999 OPENCODE_SERVER_PASSWORD=secret ./start.sh
```

### Config File Not Found

The script creates a minimal config if none exists. Add your API keys:

```bash
nano ~/.config/opencode/opencode.json
```

### Nix Build Fails

If you don't have Nix installed, use the Dockerfile build:

```bash
# The script falls back automatically
./start.sh --build
```

### Permission Denied

Ensure the workspace directory has correct permissions:

```bash
chmod 755 ./workspace
```

---

## Building from Source

### With Nix (Recommended)

```bash
nix --extra-experimental-features 'nix-command flakes' build .#default
docker load < result
```

### Without Nix

A `Dockerfile.alpine` is included for systems without Nix:

```bash
docker compose build
```

---

## License

MIT License — See [LICENSE](LICENSE) for details.

---

## Acknowledgments

- [grigio/docker-nixuser](https://github.com/grigio/docker-nixuser) — Original Nix-in-Docker approach
- [anomalyco/opencode](https://github.com/anomalyco/opencode) — OpenCode itself
