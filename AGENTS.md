# Container Tools Reference

This document describes the tools available in the OpenCode server container.

## Package Managers

### Nix (Primary)

The Nix package manager is installed and allows you to install **any of 80,000+ packages** from the Nixpkgs repository.

> **Important:** Always use `nix profile install` (not `nix-env -iA`).
> The two profile systems are incompatible and mixing them causes conflicts.

**Basic commands:**
```bash
# Search for packages
nix search nixpkgs ripgrep

# Install a package (per-user, no sudo needed)
nix profile install nixpkgs#ripgrep

# Install multiple packages
nix profile install nixpkgs#fd nixpkgs#bat nixpkgs#eza

# List installed packages
nix profile list

# Remove a package
nix profile remove ripgrep

# Update all packages
nix profile upgrade '.*'
```

**Common useful packages:**
```bash
# Modern CLI replacements
nix profile install nixpkgs#ripgrep    # rg - fast grep
nix profile install nixpkgs#fd         # fd - fast find
nix profile install nixpkgs#bat        # bat - syntax highlighting cat
nix profile install nixpkgs#eza        # eza - modern ls
nix profile install nixpkgs#fzf        # fzf - fuzzy finder
nix profile install nixpkgs#zoxide     # zoxide - smart cd

# Development tools
nix profile install nixpkgs#delta      # git diff syntax highlighting
nix profile install nixpkgs#lazygit    # terminal git UI
nix profile install nixpkgs#direnv     # directory-specific env vars
nix profile install nixpkgs#just       # command runner (like make)

# Language servers (if not already installed via bun)
nix profile install nixpkgs#lua-language-server
nix profile install nixpkgs#nil        # Nix LSP
nix profile install nixpkgs#terraform-ls
nix profile install nixpkgs#clang-tools

# Databases
nix profile install nixpkgs#postgresql
nix profile install nixpkgs#redis
nix profile install nixpkgs#mongodb

# Cloud tools
nix profile install nixpkgs#awscli2
nix profile install nixpkgs#google-cloud-sdk
nix profile install nixpkgs#azure-cli
nix profile install nixpkgs#terraform
nix profile install nixpkgs#kubectl
nix profile install nixpkgs#helm
```

### Bun (Node.js packages)

Bun is a fast JavaScript runtime and package manager.

```bash
# Install global packages
bun install -g <package>

# Run TypeScript files directly
bun run script.ts

# Start a dev server
bun dev
```

### uv (Python packages)

Modern Python package manager (much faster than pip).

```bash
# Install packages
uv pip install requests

# Create virtual environment
uv venv
source .venv/bin/activate

# Run Python
uv run python script.py
```

## Pre-installed Language Servers

Language servers provide IDE features (autocomplete, go-to-definition, diagnostics):

| Language | Server | Command |
|----------|--------|---------|
| TypeScript | typescript-language-server | ✓ pre-installed |
| Vue | vtsls | ✓ pre-installed |
| JavaScript/TS/JSON | biome | ✓ pre-installed |
| HTML/CSS/JSON/ESLint | vscode-langservers-extracted | ✓ pre-installed |
| Python | pyright | ✓ pre-installed |
| YAML | yaml-language-server | ✓ pre-installed |
| Bash | bash-language-server | ✓ pre-installed |
| Dockerfile | dockerfile-language-server-nodejs | ✓ pre-installed |
| Go | gopls | via Nix |
| Rust | rust-analyzer | via Nix |
| Lua | lua-language-server | via Nix |

## Pre-installed Tools

### Languages & Runtimes
- Node.js 22 + npm
- Bun (canary)
- Python 3.12 + uv
- Go 1.26
- Rust + Cargo

### Database Clients
- postgresql-client
- redis-cli
- sqlite3

### Utilities
- git
- curl, wget
- jq, yq
- make, cmake
- gcc, g++
- nano, vim
- htop

### AST Tools
- **ast-grep** - AST-based code search and replace

```bash
# Search for patterns
sg -p 'console.log($$$)' -l ts

# Rewrite code
sg -p 'var $A = $B' -r 'const $A = $B' -l ts --fix

# Run rules
sg scan
```

## Installing Additional Tools

If you need a tool not listed here:

1. **First, check if it's in Nix:**
   ```bash
   nix search nixpkgs <tool-name>
   ```

2. **If found, install via Nix:**
   ```bash
   nix profile install nixpkgs#<tool-name>
   ```

3. **If it's a Node.js tool, use Bun:**
   ```bash
   bun install -g <package-name>
   ```

4. **If it's a Python tool, use uv:**
   ```bash
   uv pip install <package-name>
   ```

5. **If all else fails, ask the AI to install it for you!**

## Persistent Storage

Packages installed via Nix and Bun are persisted between container restarts via Docker volumes:
- `/nix` - Nix store
- `/home/opencode/.local` - Bun global packages and uv tools
- `/home/opencode/.cache` - Package caches

> **Note:** Named Docker volumes are empty on first mount. The container entrypoint
> automatically copies build-time content into fresh volumes. Subsequent restarts
> preserve your installed packages.

## Notes

- Nix flakes are enabled (`experimental-features = nix-command flakes`)
- The user `opencode` is trusted for Nix operations
- Sandbox is disabled for compatibility
- 30 nix build users are configured for multi-user mode
- Auto-update on container start can be disabled with `OPENCODE_AUTO_UPDATE=false`
