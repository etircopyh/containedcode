# OpenCode Server - Secure Container

A production-ready Docker setup for running OpenCode server with complete isolation, full development tooling, and unlimited package installation via Nix.

## Features

- **Complete Isolation**: No access to host `$HOME`, only mounted workspace
- **Password Protected**: Server requires authentication via `OPENCODE_SERVER_PASSWORD`
- **Pre-installed Tools**: git, node, python, go, rust, postgresql, redis, mongodb, and more
- **Unlimited Autonomy**: Nix package manager with 60,000+ packages for on-demand installation
- **Non-root User**: Runs as UID 1000 for security best practices
- **Configurable Port**: Change via `PORT` environment variable
- **Read-only Config**: Your `opencode.json` with API keys is mounted read-only

## Quick Start

```bash
# 1. Start the server (will prompt for password if not set)
OPENCODE_SERVER_PASSWORD=your-secret-password ./start.sh

# 2. Connect from any OpenCode client
opencode attach http://localhost:8888
# Username: opencode
# Password: your-secret-password
```

## Requirements

- Docker (required)
- Nix with flakes support (optional, for building from source)

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

## Project Management

The workspace uses **project subdirectories** - one server, multiple projects accessible inside.

### Adding Projects

**Option 1: Copy project into workspace** (isolated copy)
```bash
./project.sh copy ~/projects/my-app
```

**Option 2: Mount external project** (live sync with original)
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

### Switching Projects in Web UI

**Important**: The OpenCode Web UI is different from the Desktop app:
- **Desktop App**: Has a native directory picker to open any project
- **Web UI**: The entire `/workspace` is treated as one project

When using the web interface:

1. All mounted projects are subdirectories of `/workspace`
2. Tell the AI to navigate: `cd /workspace/my-project`
3. All your projects are accessible within this single workspace

Example:
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
- **Mount**: Changes sync live with original directory (requires server restart)
- **Copy**: Isolated copy, changes don't affect original

## Configuration

### OpenCode Config Directory

Your entire `~/.config/opencode/` directory is mounted read-only into the container. This includes:
- `opencode.json` - Main config with API keys and providers
- `oh-my-opencode.json` - Plugin configuration
- Any other config files

To use a different config directory:

```bash
OPENCODE_CONFIG_DIR=/path/to/opencode-config OPENCODE_SERVER_PASSWORD=secret ./start.sh
```

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENCODE_SERVER_PASSWORD` | Yes | - | Password for server authentication |
| `PORT` | No | 8888 | Server port |
| `OPENCODE_CONFIG_DIR` | No | `~/.config/opencode` | Path to config directory |

## Project Structure

```
.
├── flake.nix           # Nix container definition
├── docker-compose.yml  # Docker Compose configuration
├── start.sh            # Launcher script
├── project.sh          # Project management helper
├── komodo.toml         # Komodo deployment config
├── README.md           # This file
└── workspace/          # Your project files go here
```

## Komodo Deployment

This project is ready for deployment via [Komodo](https://github.com/moghtech/komodo).

### Option 1: Git-based Deployment (Recommended)

1. Push this repo to your git server
2. In Komodo UI, create a new **Stack** resource
3. Configure:
   - Server ID: Your target server
   - Git Provider, Account, Repo, Branch
   - File Paths: `docker-compose.yml`
4. Add secret in Komodo Settings → Variables:
   - `OPENCODE_SERVER_PASSWORD` = your-password
5. In Stack environment, use: `OPENCODE_SERVER_PASSWORD = [[OPENCODE_SERVER_PASSWORD]]`
6. Deploy

### Option 2: UI-based Compose

1. In Komodo UI, create a new **Stack**
2. Paste the contents of `docker-compose.yml` into the compose editor
3. Add environment variables in the Stack settings
4. Deploy

### Required Secrets

| Secret | Description |
|--------|-------------|
| `OPENCODE_SERVER_PASSWORD` | Password for server authentication |

### Komodo Files

| File | Purpose |
|------|---------|
| `komodo.toml` | Stack resource definition template |
| `.kminclude` | Files to sync to Komodo |

## Security

### What's Protected

1. **No Host Access**: Container has no access to your `$HOME` directory
2. **Read-only Config**: `opencode.json` is mounted read-only
3. **Non-root User**: All processes run as UID 1000
4. **Password Required**: Server rejects connections without valid credentials
5. **No New Privileges**: Container cannot gain additional capabilities

### What to Be Aware Of

- **Workspace Access**: The container has full read/write access to `./workspace`
- **Network**: Server binds to `127.0.0.1` by default (local access only)
- **Nix Store**: Installed packages persist in a Docker volume

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
```

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

## Connecting Remotely

### From Another Machine

1. **SSH Tunnel** (recommended):

```bash
ssh -L 8888:localhost:8888 user@server
opencode attach http://localhost:8888
```

2. **Direct Access** (requires changing hostname):

Edit `docker-compose.yml` and change `HOSTNAME` to `0.0.0.0`, then ensure firewall allows access.

### Answer: Can Remote OpenCode Edit Local Files?

**No.** When you connect to a remote OpenCode server:
- You can ONLY edit files on that server
- The server CANNOT access your local files
- To work on local files, mount them into the container

This is a security feature - your local machine stays isolated.

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

## Building from Source

### With Nix (Recommended)

```bash
nix --extra-experimental-features 'nix-command flakes' build .#default
docker load < result
```

### Without Nix

A `Dockerfile.nix` is included for systems without Nix:

```bash
docker compose build
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- [grigio/docker-nixuser](https://github.com/grigio/docker-nixuser) - Original Nix-in-Docker approach
- [anomalyco/opencode](https://github.com/anomalyco/opencode) - OpenCode itself
