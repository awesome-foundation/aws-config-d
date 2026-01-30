#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    if "$@"; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

# --- bash tests ---

test_bash_install() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /tmp/out 2>&1
        grep -q "added: hook to.*\.bashrc" /tmp/out
    '
}

test_bash_rebuild_on_change() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # simulate a change
        sleep 1
        touch "$HOME/.aws/config.d/00-defaults"

        # source the rc file and capture output
        output=$(bash -c "source $HOME/.bashrc" 2>&1)
        echo "$output" | grep -q "aws: rebuilt"
    '
}

test_bash_no_rebuild_when_unchanged() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # source without changes — should produce no rebuild message
        output=$(bash -c "source $HOME/.bashrc" 2>&1)
        if echo "$output" | grep -q "aws: rebuilt"; then exit 1; fi
    '
}

test_bash_idempotent_install() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        ./install.sh > /tmp/out 2>&1
        grep -q "skip: hook already present" /tmp/out
    '
}

test_bash_config_content() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        grep -q "\[profile acme-dev\]" "$HOME/.aws/config" &&
        grep -q "\[profile globex-sandbox\]" "$HOME/.aws/config" &&
        grep -q "\[default\]" "$HOME/.aws/config"
    '
}

# --- zsh tests ---

test_zsh_install() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro zshusers/zsh:latest sh -c '
        apk add --no-cache bash findutils > /dev/null 2>&1
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.zshrc"
        bash ./install.sh > /tmp/out 2>&1
        grep -q "added: hook to.*\.zshrc" /tmp/out
    '
}

test_zsh_rebuild_on_change() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro zshusers/zsh:latest sh -c '
        apk add --no-cache bash findutils > /dev/null 2>&1
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.zshrc"
        bash ./install.sh > /dev/null 2>&1

        sleep 1
        touch "$HOME/.aws/config.d/00-defaults"

        output=$(zsh -c "source $HOME/.zshrc" 2>&1)
        echo "$output" | grep -q "aws: rebuilt"
    '
}

test_zsh_no_rebuild_when_unchanged() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro zshusers/zsh:latest sh -c '
        apk add --no-cache bash findutils > /dev/null 2>&1
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.zshrc"
        bash ./install.sh > /dev/null 2>&1

        output=$(zsh -c "source $HOME/.zshrc" 2>&1)
        if echo "$output" | grep -q "aws: rebuilt"; then exit 1; fi
    '
}

# --- fish tests ---

test_fish_install() {
    docker run --rm --entrypoint bash -v "$SCRIPT_DIR":/src:ro purefish/docker-fish:latest -c '
        cp -r /src /tmp/work && cd /tmp/work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.config/fish"
        ./install.sh > /tmp/out 2>&1
        grep -q "added: hook to.*config.fish" /tmp/out
    '
}

test_fish_rebuild_on_change() {
    docker run --rm --entrypoint bash -v "$SCRIPT_DIR":/src:ro purefish/docker-fish:latest -c '
        cp -r /src /tmp/work && cd /tmp/work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.config/fish"
        ./install.sh > /dev/null 2>&1

        sleep 1
        touch "$HOME/.aws/config.d/00-defaults"

        output=$(fish -c "source $HOME/.config/fish/config.fish" 2>&1)
        echo "$output" | grep -q "aws: rebuilt"
    '
}

test_fish_no_rebuild_when_unchanged() {
    docker run --rm --entrypoint bash -v "$SCRIPT_DIR":/src:ro purefish/docker-fish:latest -c '
        cp -r /src /tmp/work && cd /tmp/work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.config/fish"
        ./install.sh > /dev/null 2>&1

        output=$(fish -c "source $HOME/.config/fish/config.fish" 2>&1)
        if echo "$output" | grep -q "aws: rebuilt"; then exit 1; fi
    '
}

# --- run all tests ---

echo "=== bash ==="
run_test "bash: install adds hook to .bashrc" test_bash_install
run_test "bash: rebuilds config when file touched" test_bash_rebuild_on_change
run_test "bash: no rebuild when unchanged" test_bash_no_rebuild_when_unchanged
run_test "bash: idempotent install" test_bash_idempotent_install
run_test "bash: config contains all profiles" test_bash_config_content

echo ""
echo "=== zsh ==="
run_test "zsh: install adds hook to .zshrc" test_zsh_install
run_test "zsh: rebuilds config when file touched" test_zsh_rebuild_on_change
run_test "zsh: no rebuild when unchanged" test_zsh_no_rebuild_when_unchanged

echo ""
echo "=== fish ==="
run_test "fish: install adds hook to config.fish" test_fish_install
run_test "fish: rebuilds config when file touched" test_fish_rebuild_on_change
run_test "fish: no rebuild when unchanged" test_fish_no_rebuild_when_unchanged

echo ""
echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
