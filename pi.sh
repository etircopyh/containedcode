#!/usr/bin/env bash
#
# Pi agent helper for the OpenCode server container
#
# Manage the Pi coding agent running inside tmux.
#
# Usage:
#   ./pi.sh attach       Attach to the Pi tmux session
#   ./pi.sh send "msg"   Send a message to Pi (for RPC/headless mode)
#   ./pi.sh restart      Restart Pi inside tmux
#   ./pi.sh logs         Show Pi session output
#   ./pi.sh status       Check if Pi is running
#   ./pi.sh shell        Open a new shell in the container
#   ./pi.sh install pkg Install a Pi package

set -e

CONTAINER="opencode-server"
# All tmux/pi commands must run as the opencode user since the tmux
# session and Pi process are owned by that user.
EXEC="docker exec --user opencode -e TERM=xterm-256color"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ensure_running() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo -e "${RED}Container is not running. Start it first: ./start.sh${NC}"
        exit 1
    fi
}

cmd="${1:-attach}"

case "$cmd" in
    attach|a)
        ensure_running
        echo -e "${CYAN}Attaching to Pi tmux session...${NC}"
        echo -e "${YELLOW}Detach with: Ctrl+b then d${NC}"
        echo ""
        docker exec -it --user opencode -e TERM=xterm-256color "$CONTAINER" tmux attach -t pi
        ;;

    send|s)
        shift
        if [[ -z "$1" ]]; then
            echo "Usage: ./pi.sh send \"your message here\""
            exit 1
        fi
        ensure_running
        echo -e "${CYAN}Sending to Pi: $1${NC}"
        $EXEC "$CONTAINER" tmux send-keys -t pi "$1" Enter
        ;;

    restart|r)
        ensure_running
        echo -e "${CYAN}Restarting Pi in tmux...${NC}"
        PI_CMD="${PI_COMMAND:-pi}"
        PI_ARGS="${PI_ARGS:-}"
        # Kill the entire tmux session and recreate it cleanly.
        # This avoids the old text-into-Pi's-editor problem.
        $EXEC "$CONTAINER" tmux kill-session -t pi 2>/dev/null || true
        sleep 1
        $EXEC "$CONTAINER" tmux new-session -d -s pi -x 200 -y 50
        $EXEC "$CONTAINER" tmux send-keys -t pi "source ~/.bashrc 2>/dev/null; cd /workspace && $PI_CMD $PI_ARGS" Enter
        echo -e "${GREEN}Pi restarted. Attach with: ./pi.sh attach${NC}"
        ;;

    logs|l)
        ensure_running
        $EXEC "$CONTAINER" tmux capture-pane -t pi -p -S -100
        ;;

    status|st)
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
            echo -e "${RED}Container is not running${NC}"
            exit 1
        fi
        if $EXEC "$CONTAINER" tmux has-session -t pi 2>/dev/null; then
            echo -e "${GREEN}Pi is running in tmux session 'pi'${NC}"
            echo -e "  Attach:  ${CYAN}./pi.sh attach${NC}"
            echo -e "  SSH:     ${CYAN}ssh -p 2222 opencode@localhost${NC}"
        else
            echo -e "${YELLOW}Container running but Pi tmux session not found${NC}"
        fi
        ;;

    shell|sh)
        ensure_running
        echo -e "${CYAN}Opening shell in container as opencode...${NC}"
        docker exec -it --user opencode -e TERM=xterm-256color -w /workspace "$CONTAINER" /bin/bash
        ;;

    install|i)
        shift
        if [[ -z "$1" ]]; then
            echo "Usage: ./pi.sh install <package-source>"
            echo "  e.g.: ./pi.sh install @mariozechner/pi-coding-agent"
            echo "  e.g.: ./pi.sh install ./my-extension.ts"
            exit 1
        fi
        ensure_running
        echo -e "${CYAN}Installing Pi package: $1${NC}"
        docker exec -it --user opencode -e TERM=xterm-256color -w /workspace "$CONTAINER" pi install "$1"
        ;;

    update|u)
        ensure_running
        echo -e "${CYAN}Updating Pi...${NC}"
        docker exec -it --user opencode -e TERM=xterm-256color "$CONTAINER" pi update
        ;;

    ssh-help)
        echo "SSH Remote Access Setup"
        echo "======================="
        echo ""
        echo "1. Add your public key to ~/.ssh/authorized_keys on the HOST:"
        echo "   echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys"
        echo ""
        echo "2. Connect from another machine:"
        echo "   ssh -p 2222 opencode@<server-ip>"
        echo ""
        echo "3. Once connected, attach to Pi:"
        echo "   tmux attach -t pi"
        echo ""
        echo "4. Detach without stopping Pi:"
        echo "   Ctrl+b then d"
        echo ""
        echo "5. Resume later:"
        echo "   tmux attach -t pi"
        ;;

    *)
        echo "Pi Agent Helper"
        echo ""
        echo "Usage: ./pi.sh <command>"
        echo ""
        echo "Commands:"
        echo "  attach           Attach to Pi tmux session (default)"
        echo "  send \"msg\"      Send a message to Pi"
        echo "  restart          Restart Pi inside tmux"
        echo "  logs             Show recent Pi output"
        echo "  status           Check if Pi is running"
        echo "  shell            Open a bash shell in the container"
        echo "  install <pkg>    Install a Pi package"
        echo "  update           Update Pi and packages"
        echo "  ssh-help         Show SSH remote access instructions"
        ;;
esac
