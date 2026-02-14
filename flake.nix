{
  description = "Secure OpenCode Server Container with Nix package manager for unlimited autonomy";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = inputs@{ self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };
    in {
      default = pkgs.dockerTools.buildLayeredImage {
        name = "opencode-server";
        tag = "latest";

        # Comprehensive development environment
        contents = with pkgs; [
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
          python312
          go_1_23
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

          # Nix configuration
          (writeTextDir "etc/nix/nix.conf" ''
            experimental-features = nix-command flakes
            substituters = https://cache.nixos.org/
            trusted-users = root opencode
            sandbox = false
            build-users-group =
            ssl-cert-file = ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            require-sigs = false
          '')

          # User configuration
          (writeTextDir "etc/passwd" ''
            root:x:0:0::/root:/bin/bash
            opencode:x:1000:1000::/home/opencode:/bin/bash
          '')
          (writeTextDir "etc/group" ''
            root:x:0:
            opencode:x:1000:
            nixbld:x:30000:1000
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

          # Permission setup script
          (writeScriptBin "setup-permissions" ''
            #!/bin/bash
            set -e
            
            # Nix store permissions
            mkdir -p /nix/store/.links
            mkdir -p /nix/var/nix/{db,profiles,gcroots,temproots,userpool}
            mkdir -p /nix/var/nix/profiles/per-user/1000
            chown -R 1000:1000 /nix
            chmod -R 755 /nix

            # User home directory
            mkdir -p /home/opencode/.config/opencode
            mkdir -p /home/opencode/.local/state
            mkdir -p /home/opencode/.cache
            echo "" > /home/opencode/.bashrc
            chown -R 1000:1000 /home/opencode
            chmod -R 755 /home/opencode

            # Workspace directory
            chown -R 1000:1000 /workspace
            chmod -R 755 /workspace
          '')

          # Container initialization script
          (writeScriptBin "init-container" ''
            #!/bin/bash
            /bin/setup-permissions
          '')

          # Main entrypoint
          (writeScriptBin "entrypoint" ''
            #!/bin/bash
            set -e

            # Setup permissions as root
            /bin/setup-permissions

            # Determine port (default 8888)
            PORT="${PORT:-8888}"
            HOSTNAME="${HOSTNAME:-127.0.0.1}"

            # Change to workspace
            cd /workspace

            # Switch to opencode user and run server
            exec setpriv --reuid=1000 --regid=1000 --init-groups \
              env HOME=/home/opencode \
                  USER=opencode \
                  NIX_REMOTE= \
                  OPENCODE_SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD" \
                  opencode serve --hostname "$HOSTNAME" --port "$PORT"
          '')

          # Shell entrypoint for debugging/interactive use
          (writeScriptBin "shell-entrypoint" ''
            #!/bin/bash
            set -e

            /bin/setup-permissions

            cd /workspace

            exec setpriv --reuid=1000 --regid=1000 --init-groups \
              env HOME=/home/opencode \
                  USER=opencode \
                  NIX_REMOTE= \
                  bash
          '')
        ];

        config = {
          WorkingDir = "/workspace";
          Entrypoint = [ "/bin/entrypoint" ];
          Env = [
            "HOME=/tmp"
            "USER=opencode"
            "PATH=/bin:/usr/bin:/home/opencode/.nix-profile/bin:/nix/var/nix/profiles/default/bin"
            "TMPDIR=/home/opencode/.cache"
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
