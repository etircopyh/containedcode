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
if [ "${OPENCODE_AUTO_UPDATE:-true}" = "true" ]; then
    echo "Checking for opencode updates..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) MUSL_PKG="opencode-linux-x64-musl" ;;
        aarch64) MUSL_PKG="opencode-linux-arm64-musl" ;;
        *) MUSL_PKG="" ;;
    esac
    su - opencode -c 'bun install -g opencode-ai@latest' 2>/dev/null || echo "Update failed, continuing..."
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

# --- Start Pi in tmux ---
echo "Starting Pi in tmux session..."
PI_CMD="${PI_COMMAND:-pi}"
PI_ARGS="${PI_ARGS:-}"

# Create tmux session as opencode user
su - opencode -c 'tmux new-session -d -s pi -x 200 -y 50'

# Send the Pi start command — source bashrc first to get PATH, then run Pi
su - opencode -c "tmux send-keys -t pi 'source ~/.bashrc 2>/dev/null; cd /workspace && $PI_CMD $PI_ARGS' Enter"

echo "Pi running in tmux session 'pi'"
echo "Connect: docker exec -it --user opencode opencode-server tmux attach"
echo "Or SSH:  ssh -p 2222 opencode@localhost"

# --- Optionally start OpenCode server ---
if [ "${OPENCODE_SERVER_ENABLED:-false}" = "true" ]; then
    PORT="${PORT:-8888}"
    HOSTNAME="${HOSTNAME:-0.0.0.0}"
    echo "Starting OpenCode server on port $PORT..."
    su - opencode -c "cd /workspace && opencode serve --hostname $HOSTNAME --port $PORT" &
    OPENCODE_PID=$!
fi

# --- Keep container alive ---
if [ -n "$OPENCODE_PID" ]; then
    wait $OPENCODE_PID
else
    while su - opencode -c 'tmux has-session -t pi' 2>/dev/null; do
        sleep 5
    done
    echo "Pi tmux session ended. Exiting."
fi
