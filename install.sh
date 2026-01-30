#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create config.d directory
mkdir -p ~/.aws/config.d

# Copy example files (skip if real files already exist)
for f in "$SCRIPT_DIR"/config.d/*; do
    basename="$(basename "$f")"
    if [ -f ~/.aws/config.d/"$basename" ]; then
        echo "skip: ~/.aws/config.d/$basename already exists"
    else
        cp "$f" ~/.aws/config.d/"$basename"
        echo "copied: ~/.aws/config.d/$basename"
    fi
done

# Detect shell and install hook
install_hook() {
    local rc_file="$1"
    local snippet_file="$2"

    if [ -f "$rc_file" ]; then
        if grep -q "aws/config.d" "$rc_file"; then
            echo "skip: hook already present in $rc_file"
            return
        fi
    fi

    # Append snippet to rc file (create if missing)
    {
        echo ""
        cat "$snippet_file"
    } >> "$rc_file"
    echo "added: hook to $rc_file"
}

installed_any=false

# bash
if [ -f ~/.bashrc ] || [[ "${SHELL:-}" == */bash ]]; then
    install_hook ~/.bashrc "$SCRIPT_DIR/config.bash.snippet"
    installed_any=true
fi

# zsh
if [ -f ~/.zshrc ] || [[ "${SHELL:-}" == */zsh ]]; then
    install_hook ~/.zshrc "$SCRIPT_DIR/config.zsh.snippet"
    installed_any=true
fi

# fish
if [ -d ~/.config/fish ] || command -v fish >/dev/null 2>&1; then
    mkdir -p ~/.config/fish
    fish_config=~/.config/fish/config.fish
    if [ -f "$fish_config" ] && grep -q "aws/config.d" "$fish_config"; then
        echo "skip: hook already present in $fish_config"
    else
        {
            echo ""
            cat "$SCRIPT_DIR/config.fish.snippet"
        } >> "$fish_config"
        echo "added: hook to $fish_config"
    fi
    installed_any=true
fi

if [ "$installed_any" = false ]; then
    echo "warn: could not detect your shell, install a snippet manually:"
    echo "  bash: add contents of config.bash.snippet to ~/.bashrc"
    echo "  zsh:  add contents of config.zsh.snippet to ~/.zshrc"
    echo "  fish: add contents of config.fish.snippet to ~/.config/fish/config.fish"
fi

# Trigger initial build
cat ~/.aws/config.d/* > ~/.aws/config
echo "built: ~/.aws/config from config.d/"
echo "done!"
