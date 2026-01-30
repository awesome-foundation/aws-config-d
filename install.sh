#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create config.d directory and disabled/ subfolder
mkdir -p ~/.aws/config.d/disabled

# Always ensure 00-defaults exists with the managed-file header
if [ ! -f ~/.aws/config.d/00-defaults ]; then
    cp "$SCRIPT_DIR/config.d/00-defaults" ~/.aws/config.d/00-defaults
    echo "created: ~/.aws/config.d/00-defaults"
fi

# Migrate existing config if present and no other config.d files exist yet
existing_files=$(find ~/.aws/config.d -maxdepth 1 -type f ! -name '00-defaults' ! -name '*.example' 2>/dev/null)
if [ -f ~/.aws/config ] && [ -z "$existing_files" ]; then
    cp ~/.aws/config ~/.aws/config.d/01-migrated-config
    echo "migrated: ~/.aws/config -> ~/.aws/config.d/01-migrated-config"
    echo ""
    echo "  Your existing config has been moved to ~/.aws/config.d/01-migrated-config."
    echo "  Split it into per-organization files under ~/.aws/config.d/ at your convenience."
    echo "  For example, move [profile acme-*] and [sso-session acme] sections"
    echo "  into ~/.aws/config.d/acme, then remove them from 01-migrated-config."
    echo ""
elif [ -z "$existing_files" ]; then
    # Fresh install with no existing config — copy example files
    for f in "$SCRIPT_DIR"/config.d/*.example; do
        [ -f "$f" ] || continue
        basename="$(basename "$f")"
        cp "$f" ~/.aws/config.d/"$basename"
        echo "copied: ~/.aws/config.d/$basename"
    done
fi

# Install aws-config-d command
install_dir="${INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$install_dir"
cp "$SCRIPT_DIR/bin/aws-config-d" "$install_dir/aws-config-d"
chmod +x "$install_dir/aws-config-d"
echo "installed: aws-config-d -> $install_dir/aws-config-d"

# Ensure install dir is in PATH for current session
case ":$PATH:" in
    *:"$install_dir":*) ;;
    *) export PATH="$install_dir:$PATH" ;;
esac

# Detect shell and install hook
install_hook() {
    local rc_file="$1"
    local snippet_file="$2"

    if [ -f "$rc_file" ]; then
        if grep -q "aws-config-d" "$rc_file"; then
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
    if [ -f "$fish_config" ] && grep -q "aws-config-d" "$fish_config"; then
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
aws-config-d force
echo "done!"
