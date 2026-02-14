#!/usr/bin/env bash
#
# OpenCode Server - Secure Container Launcher
#
# Usage:
#   OPENCODE_SERVER_PASSWORD=secret ./start.sh [OPTIONS]
#
# Options:
#   --build       Force rebuild the image
#   --detach, -d  Run in background
#   --logs        Show logs after starting (implies --detach)
#   --shell       Open interactive shell instead of server
#   --stop        Stop the running container
#   --help        Show this help message
#
# Environment Variables:
#   OPENCODE_SERVER_PASSWORD  (required) Password for server authentication
#   PORT                       (optional) Server port (default: 8888)
#   OPENCODE_CONFIG_DIR        (optional) Path to config directory (default: ~/.config/opencode)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PORT="${PORT:-8888}"
BUILD=false
DETACH=false
SHOW_LOGS=false
SHELL_MODE=false
STOP_MODE=false
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

# Expand tilde in config path
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD=true
            shift
            ;;
        --detach|-d)
            DETACH=true
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
            head -30 "$0" | tail -28
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run './start.sh --help' for usage"
            exit 1
            ;;
    esac
done

# Stop mode
if $STOP_MODE; then
    echo -e "${BLUE}Stopping OpenCode server...${NC}"
    docker compose down --remove-orphans
    echo -e "${GREEN}Server stopped.${NC}"
    exit 0
fi

# Check for required password
if [[ -z "$OPENCODE_SERVER_PASSWORD" ]] && ! $SHELL_MODE; then
    echo -e "${RED}ERROR: OPENCODE_SERVER_PASSWORD is required${NC}"
    echo ""
    echo "Usage:"
    echo "  OPENCODE_SERVER_PASSWORD=your-password ./start.sh"
    echo ""
    echo "For a random password:"
    echo "  OPENCODE_SERVER_PASSWORD=\$(openssl rand -base64 32) ./start.sh"
    exit 1
fi

# Check config directory exists
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo -e "${YELLOW}WARNING: Config directory not found at $CONFIG_DIR${NC}"
    echo -e "${YELLOW}Creating a minimal config directory...${NC}"
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/opencode.json" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-5"
}
EOF
    echo -e "${GREEN}Created $CONFIG_DIR/opencode.json${NC}"
    echo -e "${YELLOW}Remember to add your API keys to the config file!${NC}"
fi

# Create workspace directory if it doesn't exist
mkdir -p ./workspace

# Export for docker-compose
export OPENCODE_SERVER_PASSWORD
export PORT
export OPENCODE_CONFIG_DIR="$CONFIG_DIR"

# Build or pull image
if $BUILD || [[ ! $(docker images -q opencode-server:latest 2>/dev/null) ]]; then
    echo -e "${BLUE}Building container image...${NC}"
    
    # Check if Nix is available
    if command -v nix &> /dev/null; then
        echo -e "${BLUE}Using Nix to build...${NC}"
        nix --extra-experimental-features 'nix-command flakes' build .#default
        docker load < result
    else
        # Fall back to Dockerfile build
        echo -e "${BLUE}Using Dockerfile to build...${NC}"
        docker compose build
    fi
fi

# Run container
if $SHELL_MODE; then
    echo -e "${BLUE}Starting interactive shell...${NC}"
    echo -e "${GREEN}You are now in the container. Type 'exit' to leave.${NC}"
    docker compose run --rm opencode-server /bin/shell-entrypoint
else
    echo -e "${BLUE}Starting OpenCode server on port $PORT...${NC}"
    
    if $DETACH; then
        docker compose up -d --remove-orphans
        echo -e "${GREEN}Server started in background!${NC}"
        echo ""
        echo -e "Connect at: ${BLUE}http://localhost:$PORT${NC}"
        echo -e "Username: ${YELLOW}opencode${NC}"
        echo -e "Password: ${YELLOW}(your OPENCODE_SERVER_PASSWORD)${NC}"
        echo ""
        echo "To view logs: docker compose logs -f"
        echo "To stop: ./start.sh --stop"
        
        if $SHOW_LOGS; then
            echo ""
            echo -e "${BLUE}Showing logs (Ctrl+C to exit)...${NC}"
            docker compose logs -f
        fi
    else
        echo -e "${GREEN}Server starting... Press Ctrl+C to stop${NC}"
        docker compose up --remove-orphans
    fi
fi
