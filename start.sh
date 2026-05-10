#!/usr/bin/env bash
#
# OpenCode Server - Container Launcher
#
# Runs Pi coding agent inside tmux with SSH access for remote attach/detach.
#
# Usage:
#   ./start.sh                    Start Pi in tmux + SSH (detached)
#   ./start.sh --attach           Attach to the running Pi tmux session
#   ./start.sh --opencode         Also start the OpenCode web server
#   ./start.sh --build            Force rebuild the image
#   ./start.sh --shell            Open interactive shell inside container
#   ./start.sh --stop             Stop the container
#   ./start.sh --help             Show this help
#
# Connect from another machine:
#   ssh -p 2222 opencode@server-ip    then: tmux attach
#
# Connect locally without SSH:
#   docker exec -it opencode-server tmux attach
#
# Environment Variables:
#   OPENCODE_SERVER_PASSWORD   (optional) Password for OpenCode web server
#   PORT                       (optional) OpenCode web server port (default: 8888)
#   SSH_PORT                   (optional) SSH port mapped to host (default: 2222)
#   OPENCODE_CONFIG_DIR        (optional) Path to OpenCode config (default: ~/.config/opencode)
#   PI_CONFIG_DIR              (optional) Path to Pi config (default: ~/.pi)
#   SSH_AUTHORIZED_KEYS        (optional) Path to authorized_keys (default: ~/.ssh/authorized_keys)
#   PI_COMMAND                 (optional) Pi command override (default: pi)
#   PI_ARGS                    (optional) Extra args for Pi (e.g. "--auto-next-steps")
#   OPENCODE_AUTO_UPDATE       (optional) Auto-update on start (default: true)

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
DETACH=true           # Default to detached (Pi runs in background)
SHOW_LOGS=false
SHELL_MODE=false
STOP_MODE=false
ATTACH_MODE=false
OPENCODE_ENABLED="${OPENCODE_SERVER_ENABLED:-false}"

# Config directories
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
PI_DIR="${PI_CONFIG_DIR:-$HOME/.pi}"
SSH_KEYS="${SSH_AUTHORIZED_KEYS:-$HOME/.ssh/authorized_keys}"

# Expand tildes
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
PI_DIR="${PI_DIR/#\~/$HOME}"
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
        --opencode)
            OPENCODE_ENABLED=true
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
            echo "OpenCode Server - Container Launcher"
            echo ""
            echo "Runs Pi coding agent inside tmux with SSH access."
            echo ""
            echo "Usage: ./start.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --attach, -a    Attach to the running Pi tmux session"
            echo "  --opencode      Also start the OpenCode web server"
            echo "  --foreground    Run in foreground (not detached)"
            echo "  --build         Force rebuild the image"
            echo "  --logs          Show logs after starting (implies detached)"
            echo "  --shell         Open interactive shell inside container"
            echo "  --stop          Stop the container"
            echo "  --help          Show this help"
            echo ""
            echo "Connecting to Pi:"
            echo "  Local:    docker exec -it opencode-server tmux attach"
            echo "  Remote:   ssh -p 2222 opencode@<server-ip>"
            echo "            then: tmux attach"
            echo ""
            echo "Detaching from Pi (inside tmux):"
            echo "  Ctrl+b then d"
            echo ""
            echo "Environment Variables:"
            echo "  PI_COMMAND              Pi command (default: pi)"
            echo "  PI_ARGS                 Extra Pi args (e.g. --auto-next-steps)"
            echo "  SSH_PORT                Host SSH port (default: 2222)"
            echo "  PORT                    OpenCode web port (default: 8888)"
            echo "  OPENCODE_CONFIG_DIR     OpenCode config path (default: ~/.config/opencode)"
            echo "  PI_CONFIG_DIR           Pi config path (default: ~/.pi)"
            echo "  SSH_AUTHORIZED_KEYS     authorized_keys path (default: ~/.ssh/authorized_keys)"
            echo "  OPENCODE_AUTO_UPDATE    Auto-update on start (default: true)"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run './start.sh --help' for usage"
            exit 1
            ;;
    esac
done

# --- Attach mode: connect to existing Pi tmux session ---
if $ATTACH_MODE; then
    if ! docker ps --format '{{.Names}}' | grep -q '^opencode-server$'; then
        echo -e "${RED}Container is not running. Start it first: ./start.sh${NC}"
        exit 1
    fi
    echo -e "${CYAN}Attaching to Pi tmux session...${NC}"
    echo -e "${YELLOW}Detach with Ctrl+b then d${NC}"
    echo ""
    docker exec -it --user opencode -e TERM=xterm-256color opencode-server tmux attach -t pi
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

# Check SSH authorized keys exist
if [[ ! -f "$SSH_KEYS" ]]; then
    echo -e "${YELLOW}WARNING: SSH authorized_keys not found at $SSH_KEYS${NC}"
    echo -e "${YELLOW}You won't be able to SSH in remotely. Only docker exec will work.${NC}"
    echo -e "${YELLOW}To fix: create the file and add your public key${NC}"
    echo ""
    # Create a placeholder so the mount doesn't fail
    mkdir -p "$(dirname "$SSH_KEYS")"
    touch "$SSH_KEYS"
fi

# Check Pi config directory
if [[ ! -d "$PI_DIR" ]]; then
    echo -e "${YELLOW}Creating Pi config directory at $PI_DIR${NC}"
    mkdir -p "$PI_DIR/agent/sessions"
fi

# Check OpenCode config directory
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo -e "${YELLOW}Creating OpenCode config directory at $CONFIG_DIR${NC}"
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

# Create workspace directory
mkdir -p ./workspace

# --- Export environment for docker-compose ---
export OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"
export OPENCODE_SERVER_ENABLED="$OPENCODE_ENABLED"
export PORT
export SSH_PORT
export OPENCODE_CONFIG_DIR="$CONFIG_DIR"
export PI_CONFIG_DIR="$PI_DIR"
export SSH_AUTHORIZED_KEYS="$SSH_KEYS"
export PI_COMMAND="${PI_COMMAND:-pi}"
export PI_ARGS="${PI_ARGS:-}"
export OPENCODE_AUTO_UPDATE="${OPENCODE_AUTO_UPDATE:-true}"

# --- Build or pull image ---
if $BUILD || [[ ! $(docker images -q opencode-server:latest 2>/dev/null) ]]; then
    echo -e "${BLUE}Building container image...${NC}"
    docker compose build
fi

# --- Run container ---
if $SHELL_MODE; then
    echo -e "${BLUE}Starting interactive shell...${NC}"
    docker compose run --rm opencode-server /bin/shell-entrypoint
else
    echo -e "${BLUE}Starting container...${NC}"
    echo ""
    echo -e "  ${CYAN}Pi agent${NC}      : running in tmux session 'pi'"
    echo -e "  ${CYAN}SSH access${NC}    : ssh -p $SSH_PORT opencode@localhost"
    echo -e "  ${CYAN}Local access${NC}  : docker exec -it --user opencode opencode-server tmux attach"
    echo -e "  ${CYAN}Detach tmux${NC}   : Ctrl+b then d"
    if [[ "$OPENCODE_ENABLED" == "true" ]]; then
        echo -e "  ${CYAN}Web server${NC}   : http://localhost:$PORT"
    fi
    echo ""

    if $DETACH; then
        docker compose up -d --remove-orphans
        echo -e "${GREEN}Container started in background!${NC}"
        echo ""
        echo "Quick commands:"
        echo "  ./start.sh --attach    # Connect to Pi"
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
