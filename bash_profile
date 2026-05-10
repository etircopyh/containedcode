# Source .bashrc for interactive shells
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Ensure PATH is set even for non-interactive login shells
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.npm-global/bin:/nix/var/nix/profiles/default/bin:$PATH"
