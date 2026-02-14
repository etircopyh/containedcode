#!/usr/bin/env bash
#
# Project helper for OpenCode server
#
# Usage:
#   ./project.sh list              - List all projects
#   ./project.sh copy /path/to/src - Copy project into workspace
#   ./project.sh mount /path/to/src - Add project as bind mount (requires restart)
#   ./project.sh create myapp      - Create new project directory
#   ./project.sh shell myapp       - Open shell in specific project

set -e

WORKSPACE_DIR="./workspace"
PROJECTS_FILE="./.projects"

mkdir -p "$WORKSPACE_DIR"

expand_tilde() {
    echo "${1/#\~/$HOME}"
}

cmd="${1:-list}"
arg="${2:-}"
arg=$(expand_tilde "$arg")

case "$cmd" in
    list|ls)
        echo "Projects in workspace:"
        echo ""
        for d in "$WORKSPACE_DIR"/*/; do
            if [[ -d "$d" ]]; then
                name=$(basename "$d")
                echo "  $name"
            fi
        done
        if [[ -f "$PROJECTS_FILE" ]]; then
            echo ""
            echo "External mounts (requires server restart):"
            cat "$PROJECTS_FILE" | while read line; do
                name="${line%%:*}"
                path="${line#*:}"
                echo "  $name -> $path"
            done
        fi
        ;;
    
    copy|cp)
        if [[ -z "$arg" ]]; then
            echo "Usage: ./project.sh copy /path/to/project"
            exit 1
        fi
        if [[ ! -d "$arg" ]]; then
            echo "Error: $arg is not a directory"
            exit 1
        fi
        
        src=$(realpath "$arg")
        name=$(basename "$src")
        
        if [[ -d "$WORKSPACE_DIR/$name" ]]; then
            echo "Error: $name already exists in workspace"
            echo "Use: ./project.sh remove $name first"
            exit 1
        fi
        
        echo "Copying $src to workspace/$name ..."
        cp -r "$src" "$WORKSPACE_DIR/$name"
        echo "Copied: $name"
        ;;
    
    mount|link)
        if [[ -z "$arg" ]]; then
            echo "Usage: ./project.sh mount /path/to/project"
            exit 1
        fi
        if [[ ! -d "$arg" ]]; then
            echo "Error: $arg is not a directory"
            exit 1
        fi
        
        src=$(realpath "$arg")
        name=$(basename "$src")
        
        if [[ -d "$WORKSPACE_DIR/$name" ]]; then
            echo "Error: $name already exists in workspace"
            exit 1
        fi
        
        echo "$name:$src" >> "$PROJECTS_FILE"
        echo ""
        echo "Added mount: $name -> $src"
        echo ""
        echo "Run ./project.sh apply to update docker-compose.yml"
        ;;
    
    unmount|unlink)
        if [[ -z "$arg" ]]; then
            echo "Usage: ./project.sh unmount project-name"
            exit 1
        fi
        
        if [[ -f "$PROJECTS_FILE" ]]; then
            grep -v "^$arg:" "$PROJECTS_FILE" > "$PROJECTS_FILE.tmp" 2>/dev/null || true
            mv "$PROJECTS_FILE.tmp" "$PROJECTS_FILE"
            echo "Removed mount: $arg"
            echo "Run ./project.sh apply to update docker-compose.yml"
        fi
        ;;
    
    apply)
        if [[ ! -f "$PROJECTS_FILE" ]]; then
            echo "No external mounts configured"
            exit 0
        fi
        
        echo "Generating docker-compose.override.yml ..."
        
        cat > docker-compose.override.yml << 'HEADER'
services:
  opencode-server:
    volumes:
HEADER
        
        cat "$PROJECTS_FILE" | while read line; do
            name="${line%%:*}"
            path="${line#*:}"
            echo "      - $path:/workspace/$name:rw" >> docker-compose.override.yml
        done
        
        echo "Created docker-compose.override.yml"
        echo ""
        echo "Restart server to apply:"
        echo "  ./start.sh --stop"
        echo "  OPENCODE_SERVER_PASSWORD=... ./start.sh"
        ;;
    
    create|new)
        if [[ -z "$arg" ]]; then
            echo "Usage: ./project.sh create project-name"
            exit 1
        fi
        mkdir -p "$WORKSPACE_DIR/$arg"
        echo "Created: $WORKSPACE_DIR/$arg"
        ;;
    
    remove|rm)
        if [[ -z "$arg" ]]; then
            echo "Usage: ./project.sh remove project-name"
            exit 1
        fi
        if [[ -d "$WORKSPACE_DIR/$arg" ]]; then
            rm -rf "$WORKSPACE_DIR/$arg"
            echo "Removed: $arg"
        else
            echo "Error: $arg not found in workspace"
        fi
        ;;
    
    shell)
        if [[ -z "$arg" ]]; then
            echo "Usage: ./project.sh shell project-name"
            exit 1
        fi
        if [[ ! -d "$WORKSPACE_DIR/$arg" ]]; then
            echo "Error: Project '$arg' not found"
            ./project.sh list
            exit 1
        fi
        docker compose run --rm -w "/workspace/$arg" opencode-server /bin/shell-entrypoint
        ;;
    
    *)
        echo "Usage:"
        echo "  ./project.sh list              - List all projects"
        echo "  ./project.sh copy /path/to/src - Copy project into workspace"
        echo "  ./project.sh mount /path/to/src - Add as external mount"
        echo "  ./project.sh apply             - Generate docker-compose.override.yml"
        echo "  ./project.sh create myapp      - Create new project directory"
        echo "  ./project.sh remove myapp      - Remove project from workspace"
        echo "  ./project.sh shell myapp       - Open shell in specific project"
        ;;
esac
