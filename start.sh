#!/usr/bin/env bash
#
# ContainedCode - Universal Coding Agent Container
#
# Runs AI coding agents (Pi, Codex CLI, Amp, etc.) inside tmux
# with SSH access and an optional web IDE server.
#
# Usage:
#   ./start.sh                    Start agent in tmux + SSH (detached)
#   ./start.sh --attach           Attach to the running tmux session
#   ./start.sh --web              Also start the web IDE server (OpenCode)
#   ./start.sh --build            Force rebuild the image
#   ./start.sh --shell            Open interactive shell inside container
#   ./start.sh --stop             Stop the container
#   ./start.sh --help             Show this help
#
# Connect from another machine:
#   ssh -p 2222 opencode@server-ip    then: tmux attach
#
# Connect locally without SSH:
#   docker exec -it containedcode tmux attach
#
# Environment Variables:
#   AGENT_CMD                  Agent command (default: pi; overrides PI_COMMAND)
#   AGENT_ARGS                 Extra args for agent (overrides PI_ARGS)
#   PI_COMMAND                 Pi command override (default: pi)
#   PI_ARGS                    Extra args for Pi (e.g. --auto-next-steps)
#   WEB_SERVER_PASSWORD        Password for web IDE server (enables server)
#   WEB_SERVER_ENABLED         Force enable/disable web server (default: auto)
#   PORT                       Web server port (default: 8888)
#   SSH_PORT                   SSH port mapped to host (default: 2222)
#   WEB_CONFIG_DIR             Path to web IDE config (default: ~/.config/opencode)
#   AGENT_CONFIG_DIR           Path to agent config (default: ~/.pi)
#   SSH_AUTHORIZED_KEYS        Path to authorized_keys (default: ~/.ssh/authorized_keys)
#   AUTO_UPDATE                Auto-update opencode on start (default: true)

set -e

# Load .env file if it exists
if [[ -f ".env" ]]; then
    set -a
    source ".env"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
PORT="${PORT:-8888}"
SSH_PORT="${SSH_PORT:-2222}"
BUILD=false
DETACH=true
SHOW_LOGS=false
SHELL_MODE=false
STOP_MODE=false
ATTACH_MODE=false

# Enable web server by default when a password is configured.
# Explicit WEB_SERVER_ENABLED=false still disables it.
if [ -n "$WEB_SERVER_PASSWORD" ] && [ "${WEB_SERVER_ENABLED:-true}" != "false" ]; then
    WEB_ENABLED=true
else
    WEB_ENABLED="${WEB_SERVER_ENABLED:-false}"
fi

# Also check legacy OPENCODE_SERVER_* vars for backward compatibility
if [ "$WEB_ENABLED" != "true" ] && [ -n "$OPENCODE_SERVER_PASSWORD" ] && [ "${OPENCODE_SERVER_ENABLED:-true}" != "false" ]; then
    WEB_ENABLED=true
fi

# Config directories
CONFIG_DIR="${WEB_CONFIG_DIR:-${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}}"
AGENT_DIR="${AGENT_CONFIG_DIR:-${PI_CONFIG_DIR:-$HOME/.pi}}"
SSH_KEYS="${SSH_AUTHORIZED_KEYS:-$HOME/.ssh/authorized_keys}"

# Expand tildes
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
AGENT_DIR="${AGENT_DIR/#\~/$HOME}"
SSH_KEYS="${SSH_KEYS/#\~/$HOME}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD=true
            shift
            ;;
        --attach|-a)
            ATTACH_MODE=true
            shift
            ;;
        --web|--opencode)
            WEB_ENABLED=true
            shift
            ;;
        --foreground|-f)
            DETACH=false
            shift
            ;;
        --logs)
            DETACH=true
            SHOW_LOGS=true
            shift
            ;;
        --shell)
            SHELL_MODE=true
            shift
            ;;
        --stop)
            STOP_MODE=true
            shift
            ;;
        --help|-h)
            echo "ContainedCode - Universal Coding Agent Container"
            echo ""
            echo "Runs AI coding agents (Pi, Codex CLI, Amp, etc.) inside tmux with SSH access."
            echo "An optional web IDE server provides a browser-based coding interface."
            echo ""
            echo "Usage: ./start.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --attach, -a    Attach to the running tmux session"
            echo "  --web           Also start the web IDE server"
            echo "  --foreground    Run in foreground (not detached)"
            echo "  --build         Force rebuild the image"
            echo "  --logs          Show logs after starting (implies detached)"
            echo "  --shell         Open interactive shell inside container"
            echo "  --stop          Stop the container"
            echo "  --help          Show this help"
            echo ""
            echo "Agents (set AGENT_CMD in .env):"
            echo "  pi             Pi coding agent (default)"
            echo "  codex          Codex CLI by OpenAI"
            echo "  amp            Amp"
            echo ""
            echo "Connecting:"
            echo "  Local:    docker exec -it containedcode tmux attach"
            echo "  Remote:   ssh -p ${SSH_PORT:-2222} opencode@<server-ip>"
            echo "            then: tmux attach"
            echo ""
            echo "Detaching from tmux:"
            echo "  Ctrl+b then d"
            echo ""
            echo "Environment Variables:"
            echo "  AGENT_CMD / PI_COMMAND    Agent command (default: pi)"
            echo "  AGENT_ARGS / PI_ARGS      Extra agent args"
            echo "  WEB_SERVER_PASSWORD       Web IDE password (enables server)"
            echo "  WEB_SERVER_ENABLED        Force enable/disable web server"
            echo "  PORT                      Web server port (default: 8888)"
            echo "  SSH_PORT                  Host SSH port (default: 2222)"
            echo "  WEB_CONFIG_DIR            Web IDE config path"
            echo "  AGENT_CONFIG_DIR          Agent config path (default: ~/.pi)"
            echo "  SSH_AUTHORIZED_KEYS       authorized_keys path"
            echo "  AUTO_UPDATE               Auto-update on start (default: true)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run './start.sh --help' for usage"
            exit 1
            ;;
    esac
done

# --- Attach mode ---
if $ATTACH_MODE; then
    if ! docker ps --format '{{.Names}}' | grep -q '^containedcode$'; then
        echo -e "${RED}Container is not running. Start it first: ./start.sh${NC}"
        exit 1
    fi
    echo -e "${CYAN}Attaching to tmux session...${NC}"
    echo -e "${YELLOW}Detach with Ctrl+b then d${NC}"
    echo ""
    docker exec -it --user opencode -e TERM=xterm-256color containedcode tmux attach -t agent
    exit 0
fi

# --- Stop mode ---
if $STOP_MODE; then
    echo -e "${BLUE}Stopping container...${NC}"
    docker compose down --remove-orphans
    echo -e "${GREEN}Container stopped.${NC}"
    exit 0
fi

# --- Pre-flight checks ---

if [[ ! -f "$SSH_KEYS" ]]; then
    echo -e "${YELLOW}WARNING: SSH authorized_keys not found at $SSH_KEYS${NC}"
    echo -e "${YELLOW}You won't be able to SSH in remotely. Only docker exec will work.${NC}"
    echo ""
    mkdir -p "$(dirname "$SSH_KEYS")"
    touch "$SSH_KEYS"
fi

if [[ ! -d "$AGENT_DIR" ]]; then
    echo -e "${YELLOW}Creating agent config directory at $AGENT_DIR${NC}"
    mkdir -p "$AGENT_DIR/agent/sessions"
fi

if [[ ! -d "$CONFIG_DIR" ]]; then
    echo -e "${YELLOW}Creating web IDE config directory at $CONFIG_DIR${NC}"
    mkdir -p "$CONFIG_DIR"
    if [[ ! -f "$CONFIG_DIR/opencode.json" ]]; then
        cat > "$CONFIG_DIR/opencode.json" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-5"
}
EOF
        echo -e "${GREEN}Created $CONFIG_DIR/opencode.json${NC}"
    fi
fi

mkdir -p ./workspace

# --- Export environment for docker-compose ---
export WEB_SERVER_PASSWORD="${WEB_SERVER_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}"
export WEB_SERVER_ENABLED="$WEB_ENABLED"
export PORT
export SSH_PORT
export WEB_CONFIG_DIR="$CONFIG_DIR"
export AGENT_CONFIG_DIR="$AGENT_DIR"
export SSH_AUTHORIZED_KEYS="$SSH_KEYS"
export AGENT_CMD="${AGENT_CMD:-${PI_COMMAND:-pi}}"
export AGENT_ARGS="${AGENT_ARGS:-${PI_ARGS:-}}"
export AUTO_UPDATE="${AUTO_UPDATE:-${OPENCODE_AUTO_UPDATE:-true}}"

# --- Build or pull image ---
if $BUILD || [[ ! $(docker images -q containedcode:latest 2>/dev/null) ]]; then
    echo -e "${BLUE}Building container image...${NC}"
    docker compose build
fi

# --- Run container ---
if $SHELL_MODE; then
    echo -e "${BLUE}Starting interactive shell...${NC}"
    docker compose run --rm containedcode /bin/shell-entrypoint
else
    echo -e "${BLUE}Starting container...${NC}"
    echo ""
    echo -e "  ${CYAN}Agent${NC}         : running in tmux session 'agent'"
    echo -e "  ${CYAN}SSH access${NC}    : ssh -p $SSH_PORT opencode@localhost"
    echo -e "  ${CYAN}Local access${NC}  : docker exec -it --user opencode containedcode tmux attach"
    echo -e "  ${CYAN}Detach tmux${NC}   : Ctrl+b then d"
    if [[ "$WEB_ENABLED" == "true" ]]; then
        echo -e "  ${CYAN}Web IDE${NC}       : http://localhost:$PORT"
    fi
    echo ""

    if $DETACH; then
        docker compose up -d --remove-orphans
        echo -e "${GREEN}Container started in background!${NC}"
        echo ""
        echo "Quick commands:"
        echo "  ./start.sh --attach    # Connect to agent"
        echo "  ./start.sh --stop      # Stop everything"
        echo "  docker compose logs -f  # View logs"

        if $SHOW_LOGS; then
            echo ""
            echo -e "${BLUE}Showing logs (Ctrl+C to exit)...${NC}"
            docker compose logs -f
        fi
    else
        echo -e "${GREEN}Container starting in foreground... Press Ctrl+C to stop${NC}"
        docker compose up --remove-orphans
    fi
fi
