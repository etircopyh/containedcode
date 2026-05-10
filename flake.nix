{
  description = "Secure OpenCode Server Container with Pi coding agent and Nix package manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = inputs@{ self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };

      # Tmux config for the opencode user
      tmuxConf = pkgs.writeText "tmux.conf" ''
        set -g default-terminal "screen-256color"
        set -ga terminal-overrides ",xterm-256color:Tc"
        set -g mouse on
        setw -g mode-keys vi
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
        bind r source-file ~/.tmux.conf \; display-message "Config reloaded"
        set -g status-style "bg=#1a1b26,fg=#a9b1d6"
        set -g status-left-length 30
        set -g status-left '#[fg=#7aa2f7,bold] π opencode '
        set -g status-right '#[fg=#565f89]%H:%M %d-%b '
        set -g pane-border-style "fg=#3b4261"
        set -g pane-active-border-style "fg=#7aa2f7"
        set -sg escape-time 0
      '';

      # Bundle all custom scripts into one package to ensure they are correctly placed in /bin
      customScripts = pkgs.runCommand "custom-scripts" {} ''
        mkdir -p $out/bin

        # setup-permissions script
        cat > $out/bin/setup-permissions <<'EOF'
        #!${pkgs.bash}/bin/bash
        set -e

        # Nix store permissions
        mkdir -p /nix/store/.links
        mkdir -p /nix/var/nix/{db,profiles,gcroots,temproots,userpool}
        mkdir -p /nix/var/nix/profiles/per-user/1000
        chown -R 1000:1000 /nix 2>/dev/null || true
        chmod -R 755 /nix 2>/dev/null || true

        # User home directory - create dirs but don't fail on read-only mounts
        mkdir -p /home/opencode/.config/opencode
        mkdir -p /home/opencode/.local/state
        mkdir -p /home/opencode/.cache
        mkdir -p /home/opencode/.pi/agent/sessions
        mkdir -p /home/opencode/.ssh
        echo "" > /home/opencode/.bashrc 2>/dev/null || true

        # Chown only writable directories, ignore read-only mounts
        chown -R 1000:1000 /home/opencode/.local 2>/dev/null || true
        chown -R 1000:1000 /home/opencode/.cache 2>/dev/null || true
        chown -R 1000:1000 /home/opencode/.pi 2>/dev/null || true
        chown 1000:1000 /home/opencode/.bashrc 2>/dev/null || true
        chmod -R 755 /home/opencode/.local 2>/dev/null || true
        chmod -R 755 /home/opencode/.cache 2>/dev/null || true

        # SSH authorized_keys (read-only mount)
        chmod 600 /home/opencode/.ssh/authorized_keys 2>/dev/null || true
        chown 1000:1000 /home/opencode/.ssh/authorized_keys 2>/dev/null || true

        # Workspace directory
        chown -R 1000:1000 /workspace 2>/dev/null || true
        chmod -R 755 /workspace 2>/dev/null || true
        EOF
        chmod +x $out/bin/setup-permissions

        # entrypoint script
        cat > $out/bin/entrypoint <<'EOF'
        #!${pkgs.bash}/bin/bash
        set -e

        # Setup permissions as root
        /bin/setup-permissions

        # Start SSH daemon
        echo "Starting SSH daemon..."
        /usr/sbin/sshd

        # Start Pi in tmux session
        echo "Starting Pi in tmux session..."
        PI_CMD="${"\${PI_COMMAND:-pi}"}"
        PI_ARGS="${"\${PI_ARGS:-}"}"

        ${pkgs.util-linux}/bin/setpriv --reuid=1000 --regid=1000 --init-groups \
          env HOME=/home/opencode USER=opencode \
          tmux new-session -d -s pi -x 200 -y 50

        ${pkgs.util-linux}/bin/setpriv --reuid=1000 --regid=1000 --init-groups \
          env HOME=/home/opencode USER=opencode \
          tmux send-keys -t pi "cd /workspace && $PI_CMD $PI_ARGS" Enter

        echo "Pi running in tmux session 'pi'"

        # Optionally start OpenCode server
        if [ "${"\${OPENCODE_SERVER_ENABLED:-false}"}" = "true" ]; then
            PORT="${"\${PORT:-8888}"}"
            HOSTNAME="${"\${HOSTNAME:-0.0.0.0}"}"
            echo "Starting OpenCode server on port $PORT..."
            ${pkgs.util-linux}/bin/setpriv --reuid=1000 --regid=1000 --init-groups \
              env HOME=/home/opencode USER=opencode NIX_REMOTE= \
              OPENCODE_SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD" \
              opencode serve --hostname "$HOSTNAME" --port "$PORT" &
            OPENCODE_PID=$!
        fi

        # Keep container alive - wait for tmux session
        while ${pkgs.util-linux}/bin/setpriv --reuid=1000 --regid=1000 --init-groups \
          env HOME=/home/opencode USER=opencode \
          tmux has-session -t pi 2>/dev/null; do
            sleep 5
        done
        echo "Pi tmux session ended. Exiting."
        EOF
        chmod +x $out/bin/entrypoint

        # shell-entrypoint script
        cat > $out/bin/shell-entrypoint <<'EOF'
        #!${pkgs.bash}/bin/bash
        set -e

        /bin/setup-permissions

        cd /workspace

        exec ${pkgs.util-linux}/bin/setpriv --reuid=1000 --regid=1000 --init-groups \
          env HOME=/home/opencode \
              USER=opencode \
              NIX_REMOTE= \
              ${pkgs.bash}/bin/bash
        EOF
        chmod +x $out/bin/shell-entrypoint
      '';

    in {
      default = pkgs.dockerTools.buildLayeredImage {
        name = "opencode-server";
        tag = "latest";

        # Comprehensive development environment
        contents = with pkgs; [
          # Custom scripts
          customScripts

          # Core system
          bashInteractive
          coreutils
          nix
          cacert
          shadow
          util-linux
          sudo
          procps
          gnugrep
          gnused
          gawk
          which
          findutils
          iputils

          # Build essentials
          gnumake
          cmake
          gcc
          pkg-config

          # Version control
          git
          gh  # GitHub CLI

          # Language runtimes
          bun           # Node.js alternative
          nodejs_22
          uv            # Python package manager
          python
          go_1_24
          rustc
          cargo

          # Database clients
          postgresql    # psql client
          redis         # redis-cli
          mongodb-tools # mongosh, mongoimport, etc.
          sqlite

          # Network tools
          curl
          wget
          jq
          yq-go         # YAML processor

          # Text editors
          nano
          vim

          # Process management
          htop

          # Session management
          tmux

          # SSH server
          openssh

          # OpenCode itself
          opencode

          # Language servers for LSP support
          typescript-language-server
          typescript
          vscode-langservers-extracted  # HTML, CSS, JSON, ESLint language servers
          nixd  # Nix language server
          lua-language-server
          gopls  # Go language server
          pyright  # Python language server
          rust-analyzer
          yaml-language-server
          bash-language-server
          dockerfile-language-server-nodejs
          biome  # Fast linter/formatter for JS/TS/JSON with LSP support

          # Nix configuration
          (writeTextDir "etc/nix/nix.conf" ''
            experimental-features = nix-command flakes
            substituters = https://cache.nixos.org/
            trusted-users = root opencode
            sandbox = false
            build-users-group = nixbld
            ssl-cert-file = ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '')

          # SSH server configuration
          (writeTextDir "etc/ssh/sshd_config" ''
            Port 2222
            PasswordAuthentication no
            PubkeyAuthentication yes
            PermitRootLogin no
            AllowUsers opencode
            ClientAliveInterval 60
            ClientAliveCountMax 3
          '')

          # User configuration - nixbld1..nixbld30 users for multi-user Nix builds
          (let
            nixbldUsers = pkgs.lib.concatMapStringsSep "\n"
              (i: "nixbld${toString i}:x:${toString (30000 + i)}:30000::/var/empty:/bin/false")
              (pkgs.lib.range 1 30);
          in writeTextDir "etc/passwd" ''
            root:x:0:0::/root:/bin/bash
            opencode:x:1000:1000::/home/opencode:/bin/bash
            ${nixbldUsers}
          '')
          (writeTextDir "etc/group" ''
            root:x:0:
            opencode:x:1000:
            nixbld:x:30000:opencode
          '')
          (writeTextDir "root/.bashrc" "")

          # Tmux config
          (runCommand "tmux-config" {} ''
            mkdir -p $out/home/opencode/.tmux
            cp ${tmuxConf} $out/home/opencode/.tmux.conf
          '')

          # Bash profile for SSH sessions
          (writeTextDir "home/opencode/.bash_profile" ''
            if [ -f ~/.bashrc ]; then
              . ~/.bashrc
            fi
          '')
          (writeTextDir "home/opencode/.bashrc" ''
            export PATH="$HOME/.local/bin:$HOME/.bun/bin:/nix/var/nix/profiles/default/bin:$PATH"
            export BUN_INSTALL="$HOME/.bun"
            export HOME="/home/opencode"
            export PI_CODING_AGENT_DIR="$HOME/.pi/agent"
            export PS1='\[\033[0;34m\]\w\[\033[0m\] \$ '
          '')

          # Directory structure
          (runCommand "create-dirs" {} ''
            mkdir -p $out/nix/store/.links
            mkdir -p $out/nix/var/nix/{db,profiles,gcroots,temproots,userpool}
            mkdir -p $out/nix/var/nix/profiles/per-user/1000
            mkdir -p $out/workspace
            mkdir -p $out/home/opencode/.config/opencode
            mkdir -p $out/home/opencode/.local/state
            mkdir -p $out/home/opencode/.cache
            mkdir -p $out/home/opencode/.pi/agent/sessions
            mkdir -p $out/home/opencode/.ssh
            mkdir -p $out/run/sshd
          '')
        ];

        config = {
          WorkingDir = "/workspace";
          Entrypoint = [ "/bin/entrypoint" ];
          Env = [
            "HOME=/home/opencode"
            "USER=opencode"
            "PATH=/bin:/usr/bin:/home/opencode/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            "NIX_REMOTE_TRUSTED_PUBLIC_KEYS=cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "NIX_PATH=nixpkgs=${inputs.nixpkgs}"
            "NIX_REMOTE="
            "UMASK=022"
          ];
          ExposedPorts = {
            "8888/tcp" = {};
            "2222/tcp" = {};
          };
        };
      };
    });
  };
}
