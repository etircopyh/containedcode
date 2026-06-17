#!/bin/bash
set -e

# --- Volume initialization ---
if [ -d /opt/init-nix ] && [ -z "$(ls -A /nix/store 2>/dev/null)" ]; then
    echo "Initializing /nix volume from build image..."
    cp -a /opt/init-nix/. /nix/
fi
if [ -d /opt/init-local ] && [ -z "$(ls -A /home/opencode/.local 2>/dev/null)" ]; then
    echo "Initializing /home/opencode/.local volume from build image..."
    cp -a /opt/init-local/. /home/opencode/.local/
    chown -R opencode:opencode /home/opencode/.local
fi
if [ -d /opt/init-cache ] && [ -z "$(ls -A /home/opencode/.cache 2>/dev/null)" ]; then
    echo "Initializing /home/opencode/.cache volume from build image..."
    cp -a /opt/init-cache/. /home/opencode/.cache/
    chown -R opencode:opencode /home/opencode/.cache
fi

# --- Auto-update ---
AUTO_UPDATE="${AUTO_UPDATE:-${OPENCODE_AUTO_UPDATE:-true}}"
if [ "$AUTO_UPDATE" = "true" ]; then
    echo "Checking for opencode updates..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) MUSL_PKG="opencode-linux-x64-musl" ;;
        aarch64) MUSL_PKG="opencode-linux-arm64-musl" ;;
        *) MUSL_PKG="" ;;
    esac
    su - opencode -c 'source ~/.bashrc 2>/dev/null; bun install -g opencode-ai@latest' 2>/dev/null || echo "Update failed, continuing..."
    if [ -n "$MUSL_PKG" ]; then
        ln -sf "/home/opencode/.bun/install/global/node_modules/$MUSL_PKG/bin/opencode" \
               "/home/opencode/.bun/install/global/node_modules/opencode-ai/bin/.opencode"
    fi
    opencode --version 2>/dev/null || true
fi

# --- Start SSH daemon ---
echo "Starting SSH daemon..."
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -A
fi
/usr/sbin/sshd -e || echo "WARNING: sshd failed to start, SSH access unavailable"

# --- Start agent in tmux ---
# AGENT_CMD overrides PI_COMMAND; if neither is set, defaults to "pi"
AGENT_CMD="${AGENT_CMD:-${PI_COMMAND:-pi}}"
AGENT_ARGS="${AGENT_ARGS:-${PI_ARGS:-}}"
TMUX_SESSION="agent"

echo "Starting agent ($AGENT_CMD $AGENT_ARGS) in tmux session '$TMUX_SESSION'..."

# Create tmux session as opencode user
su - opencode -c "tmux new-session -d -s $TMUX_SESSION -x 200 -y 50"

# Send the agent start command — source bashrc first to get PATH
su - opencode -c "tmux send-keys -t $TMUX_SESSION 'source ~/.bashrc 2>/dev/null; cd /workspace && $AGENT_CMD $AGENT_ARGS' Enter"

echo "Agent running in tmux session '$TMUX_SESSION'"
echo "Connect: docker exec -it --user opencode containedcode tmux attach"
echo "Or SSH:  ssh -p 2222 opencode@localhost"

# --- Optionally start web IDE server (OpenCode) ---
# Auto-enable when password is set, unless explicitly disabled
# Supports WEB_SERVER_PASSWORD/WEB_SERVER_ENABLED (new) and OPENCODE_SERVER_PASSWORD/OPENCODE_SERVER_ENABLED (legacy)
WEB_PASSWORD="${WEB_SERVER_PASSWORD:-${OPENCODE_SERVER_PASSWORD:-}}"
WEB_ENABLED="${WEB_SERVER_ENABLED:-${OPENCODE_SERVER_ENABLED:-auto}}"
if [ "$WEB_ENABLED" != "false" ] && { [ "$WEB_ENABLED" = "true" ] || [ -n "$WEB_PASSWORD" ]; }; then
    PORT="${PORT:-8888}"
    # HOSTNAME collides with Docker's system hostname. If HOSTNAME matches
    # the container hostname, Docker auto-set it — default to 0.0.0.0.
    if [ "$HOSTNAME" = "$(hostname 2>/dev/null)" ] || [ -z "${HOSTNAME}" ]; then
        BIND_ADDR="0.0.0.0"
    else
        BIND_ADDR="$HOSTNAME"
    fi
    echo "Starting OpenCode server on port $PORT (bind: $BIND_ADDR)..."
    su - opencode -c "source ~/.bashrc 2>/dev/null; cd /workspace && env \"OPENCODE_SERVER_PASSWORD=$WEB_PASSWORD\" opencode serve --hostname $BIND_ADDR --port $PORT" &
    OPENCODE_PID=$!
fi

# --- Keep container alive (wait for tmux session) ---
while su - opencode -c "tmux has-session -t $TMUX_SESSION" 2>/dev/null; do
    sleep 5
done
echo "Tmux session '$TMUX_SESSION' ended. Exiting."
