{
  description = "Secure OpenCode Server Container with Nix package manager for unlimited autonomy";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = inputs@{ self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };

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
        echo "" > /home/opencode/.bashrc 2>/dev/null || true

        # Chown only writable directories, ignore read-only mounts
        chown -R 1000:1000 /home/opencode/.local 2>/dev/null || true
        chown -R 1000:1000 /home/opencode/.cache 2>/dev/null || true
        chown 1000:1000 /home/opencode/.bashrc 2>/dev/null || true
        chmod -R 755 /home/opencode/.local 2>/dev/null || true
        chmod -R 755 /home/opencode/.cache 2>/dev/null || true

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

        # Determine port (default 8888)
        PORT="${"\${PORT:-8888}"}"
        HOSTNAME="${"\${HOSTNAME:-0.0.0.0}"}"

        # Change to workspace
        cd /workspace

        # Switch to opencode user and run server
        exec ${pkgs.util-linux}/bin/setpriv --reuid=1000 --regid=1000 --init-groups \
          env HOME=/home/opencode \
              USER=opencode \
              NIX_REMOTE= \
              OPENCODE_SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD" \
              opencode serve --hostname "$HOSTNAME" --port "$PORT"
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
          go
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

          # Directory structure
          (runCommand "create-dirs" {} ''
            mkdir -p $out/nix/store/.links
            mkdir -p $out/nix/var/nix/{db,profiles,gcroots,temproots,userpool}
            mkdir -p $out/nix/var/nix/profiles/per-user/1000
            mkdir -p $out/workspace
            mkdir -p $out/home/opencode/.config/opencode
            mkdir -p $out/home/opencode/.local/state
            mkdir -p $out/home/opencode/.cache
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
          };
        };
      };
    });
  };
}
