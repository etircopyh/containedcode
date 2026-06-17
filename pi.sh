#!/usr/bin/env bash
#
# Agent helper for ContainedCode
#
# Manage the agent (Pi, Codex CLI, Amp, etc.) running inside tmux.
#
# Usage:
#   ./pi.sh attach       Attach to the tmux session
#   ./pi.sh send "msg"   Send a message to the agent (for RPC/headless mode)
#   ./pi.sh restart      Restart agent inside tmux
#   ./pi.sh logs         Show session output
#   ./pi.sh status       Check if agent is running
#   ./pi.sh shell        Open a new shell in the container
#   ./pi.sh install pkg  Install a Pi package

set -e

CONTAINER="containedcode"
SESSION="agent"
# All tmux/agent commands must run as the opencode user since the tmux
# session and agent process are owned by that user.
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
        echo -e "${CYAN}Attaching to tmux session...${NC}"
        echo -e "${YELLOW}Detach with: Ctrl+b then d${NC}"
        echo ""
        docker exec -it --user opencode -e TERM=xterm-256color "$CONTAINER" tmux attach -t "$SESSION"
        ;;
    
    send|s)
        shift
        if [[ -z "$1" ]]; then
            echo "Usage: ./pi.sh send \"your message here\""
            exit 1
        fi
        ensure_running
        echo -e "${CYAN}Sending to agent: $1${NC}"
        $EXEC "$CONTAINER" tmux send-keys -t "$SESSION" "$1" Enter
        ;;
    
    restart|r)
        ensure_running
        echo -e "${CYAN}Restarting agent in tmux...${NC}"
        AGENT_CMD="${AGENT_CMD:-${PI_COMMAND:-pi}}"
        AGENT_ARGS="${AGENT_ARGS:-${PI_ARGS:-}}"
        # Kill the entire tmux session and recreate it cleanly.
        # This avoids the old text-into-agent's-editor problem.
        $EXEC "$CONTAINER" tmux kill-session -t "$SESSION" 2>/dev/null || true
        sleep 1
        $EXEC "$CONTAINER" tmux new-session -d -s "$SESSION" -x 200 -y 50
        $EXEC "$CONTAINER" tmux send-keys -t "$SESSION" "source ~/.bashrc 2>/dev/null; cd /workspace && $AGENT_CMD $AGENT_ARGS" Enter
        echo -e "${GREEN}Agent restarted. Attach with: ./pi.sh attach${NC}"
        ;;
    
    logs|l)
        ensure_running
        $EXEC "$CONTAINER" tmux capture-pane -t "$SESSION" -p -S -100
        ;;
    
    status|st)
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
            echo -e "${RED}Container is not running${NC}"
            exit 1
        fi
        if $EXEC "$CONTAINER" tmux has-session -t "$SESSION" 2>/dev/null; then
            echo -e "${GREEN}Agent is running in tmux session '$SESSION'${NC}"
            echo -e "  Attach:  ${CYAN}./pi.sh attach${NC}"
            echo -e "  SSH:     ${CYAN}ssh -p 2222 opencode@localhost${NC}"
        else
            echo -e "${YELLOW}Container running but tmux session not found${NC}"
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
            echo "  e.g.: ./pi.sh install @earendil-works/pi-coding-agent"
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
        echo "3. Once connected, attach to agent:"
        echo "   tmux attach -t agent"
        echo ""
        echo "4. Detach without stopping agent:"
        echo "   Ctrl+b then d"
        echo ""
        echo "5. Resume later:"
        echo "   tmux attach -t agent"
        ;;
    
    *)
        echo "Agent Helper"
        echo ""
        echo "Usage: ./pi.sh <command>"
        echo ""
        echo "Commands:"
        echo "  attach           Attach to tmux session (default)"
        echo "  send \"msg\"      Send a message to the agent"
        echo "  restart          Restart agent inside tmux"
        echo "  logs             Show recent output"
        echo "  status           Check if agent is running"
        echo "  shell            Open a bash shell in the container"
        echo "  install <pkg>    Install a Pi package"
        echo "  update           Update Pi and packages"
        echo "  ssh-help         Show SSH remote access instructions"
        ;;
esac
