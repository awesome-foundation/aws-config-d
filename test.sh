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
        output=$(PATH="$HOME/.local/bin:$PATH" bash -c "source $HOME/.bashrc" 2>&1)
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
        output=$(PATH="$HOME/.local/bin:$PATH" bash -c "source $HOME/.bashrc" 2>&1)
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
        # fresh install only has 00-defaults and .example files
        grep -q "managed by" "$HOME/.aws/config" &&
        # .example files should NOT be in the rendered config
        if grep -q "\[profile acme-dev\]" "$HOME/.aws/config"; then exit 1; fi
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

        output=$(PATH="$HOME/.local/bin:$PATH" zsh -c "source $HOME/.zshrc" 2>&1)
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

        output=$(PATH="$HOME/.local/bin:$PATH" zsh -c "source $HOME/.zshrc" 2>&1)
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

        output=$(fish -c "set -x PATH $HOME/.local/bin \$PATH; source $HOME/.config/fish/config.fish" 2>&1)
        echo "$output" | grep -q "aws: rebuilt"
    '
}

test_fish_no_rebuild_when_unchanged() {
    docker run --rm --entrypoint bash -v "$SCRIPT_DIR":/src:ro purefish/docker-fish:latest -c '
        cp -r /src /tmp/work && cd /tmp/work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.config/fish"
        ./install.sh > /dev/null 2>&1

        output=$(fish -c "set -x PATH $HOME/.local/bin \$PATH; source $HOME/.config/fish/config.fish" 2>&1)
        if echo "$output" | grep -q "aws: rebuilt"; then exit 1; fi
    '
}

# --- migration tests ---

test_migrate_existing_config() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.aws"
        touch "$HOME/.bashrc"
        echo -e "[default]\nregion=us-east-1\n\n[profile myorg-dev]\nregion=eu-west-1" > "$HOME/.aws/config"
        ./install.sh > /tmp/out 2>&1
        grep -q "migrated:.*01-migrated-config" /tmp/out &&
        grep -q "\[profile myorg-dev\]" "$HOME/.aws/config.d/01-migrated-config" &&
        grep -q "Split it into per-organization files" /tmp/out
    '
}

test_migrate_preserves_content() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.aws"
        touch "$HOME/.bashrc"
        echo -e "[default]\nregion=us-east-1\n\n[profile foo]\nregion=eu-west-1" > "$HOME/.aws/config"
        ./install.sh > /dev/null 2>&1
        # rebuilt config should have same content as original
        grep -q "\[default\]" "$HOME/.aws/config" &&
        grep -q "\[profile foo\]" "$HOME/.aws/config"
    '
}

test_migrate_has_header_comment() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.aws"
        touch "$HOME/.bashrc"
        echo -e "[default]\nregion=us-east-1" > "$HOME/.aws/config"
        ./install.sh > /dev/null 2>&1
        head -1 "$HOME/.aws/config" | grep -q "managed by"
    '
}

test_fresh_install_has_header_comment() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        head -1 "$HOME/.aws/config" | grep -q "managed by"
    '
}

test_no_migrate_when_config_d_exists() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.aws/config.d"
        touch "$HOME/.bashrc"
        echo "[default]" > "$HOME/.aws/config"
        echo "[profile existing]" > "$HOME/.aws/config.d/existing"
        ./install.sh > /tmp/out 2>&1
        if grep -q "migrated:" /tmp/out; then exit 1; fi
    '
}

# --- drift detection tests ---

test_bash_drift_warns_on_external_edit() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # simulate external edit
        echo "# sneaky edit" >> "$HOME/.aws/config"
        sleep 1
        touch "$HOME/.aws/config.d/00-defaults"

        output=$(PATH="$HOME/.local/bin:$PATH" bash -c "source $HOME/.bashrc" 2>&1)
        echo "$output" | grep -q "WARNING"
    '
}

test_bash_drift_does_not_overwrite() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # simulate external edit
        echo "# sneaky edit" >> "$HOME/.aws/config"
        sleep 1
        touch "$HOME/.aws/config.d/00-defaults"

        PATH="$HOME/.local/bin:$PATH" bash -c "source $HOME/.bashrc" > /dev/null 2>&1
        # the sneaky edit should still be there (not overwritten)
        grep -q "sneaky edit" "$HOME/.aws/config"
    '
}

test_bash_drift_normal_rebuild_updates_hash() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # record hash after install
        hash1=$(cat "$HOME/.aws/config.d/.config.sha256")

        # trigger a normal rebuild by adding a real profile file
        sleep 1
        echo "[profile test-org]" > "$HOME/.aws/config.d/test-org"
        PATH="$HOME/.local/bin:$PATH" bash -c "source $HOME/.bashrc" > /dev/null 2>&1

        # hash should have changed
        hash2=$(cat "$HOME/.aws/config.d/.config.sha256")
        test "$hash1" != "$hash2"
    '
}

test_fish_drift_warns_on_external_edit() {
    docker run --rm --entrypoint bash -v "$SCRIPT_DIR":/src:ro purefish/docker-fish:latest -c '
        cp -r /src /tmp/work && cd /tmp/work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.config/fish"
        ./install.sh > /dev/null 2>&1

        # simulate external edit
        echo "# sneaky edit" >> "$HOME/.aws/config"
        sleep 1
        touch "$HOME/.aws/config.d/00-defaults"

        output=$(fish -c "set -x PATH $HOME/.local/bin \$PATH; source $HOME/.config/fish/config.fish" 2>&1)
        echo "$output" | grep -q "WARNING"
    '
}

# --- aws-config-d command tests ---

test_force_rebuild() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # force rebuild even though nothing changed
        export PATH="$HOME/.local/bin:$PATH"
        output=$(aws-config-d --force 2>&1)
        echo "$output" | grep -q "aws: rebuilt"
    '
}

test_force_resets_drift() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # simulate external edit (creates drift)
        echo "# sneaky edit" >> "$HOME/.aws/config"

        # force should overwrite despite drift
        export PATH="$HOME/.local/bin:$PATH"
        aws-config-d --force > /dev/null 2>&1
        if grep -q "sneaky edit" "$HOME/.aws/config"; then exit 1; fi
    '
}

test_force_without_dashes() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        export PATH="$HOME/.local/bin:$PATH"
        output=$(aws-config-d force 2>&1)
        echo "$output" | grep -q "aws: rebuilt"
    '
}

test_help_is_default() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        export PATH="$HOME/.local/bin:$PATH"
        output=$(aws-config-d 2>&1)
        echo "$output" | grep -q "Usage:"
    '
}

# --- disable tests ---

test_off_suffix_excluded() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        # create real profile files
        echo "[profile acme-dev]" > "$HOME/.aws/config.d/acme-corp"
        echo "[profile globex-sandbox]" > "$HOME/.aws/config.d/globex-inc"
        aws-config-d force > /dev/null 2>&1

        # disable acme-corp by renaming with .off suffix
        mv "$HOME/.aws/config.d/acme-corp" "$HOME/.aws/config.d/acme-corp.off"
        aws-config-d force > /dev/null 2>&1

        # acme profiles should be gone, globex should remain
        if grep -q "\[profile acme-dev\]" "$HOME/.aws/config"; then exit 1; fi
        grep -q "\[profile globex-sandbox\]" "$HOME/.aws/config"
    '
}

test_disabled_dir_excluded() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        # create real profile files
        echo "[profile acme-dev]" > "$HOME/.aws/config.d/acme-corp"
        echo "[profile globex-sandbox]" > "$HOME/.aws/config.d/globex-inc"
        aws-config-d force > /dev/null 2>&1

        # disable globex by moving to disabled/
        mv "$HOME/.aws/config.d/globex-inc" "$HOME/.aws/config.d/disabled/globex-inc"
        aws-config-d force > /dev/null 2>&1

        # globex profiles should be gone, acme should remain
        if grep -q "\[profile globex-sandbox\]" "$HOME/.aws/config"; then exit 1; fi
        grep -q "\[profile acme-dev\]" "$HOME/.aws/config"
    '
}

test_installer_creates_disabled_dir() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        test -d "$HOME/.aws/config.d/disabled"
    '
}

test_installer_updates_binary() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1

        # tamper with the installed binary
        echo "# old version" > "$HOME/.local/bin/aws-config-d"

        # re-run installer — should overwrite with latest
        ./install.sh > /dev/null 2>&1
        if grep -q "old version" "$HOME/.local/bin/aws-config-d"; then exit 1; fi
        grep -q "_rebuild" "$HOME/.local/bin/aws-config-d"
    '
}

# --- list/enable/disable tests ---

test_list_shows_enabled_and_disabled() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        echo "[profile acme-dev]" > "$HOME/.aws/config.d/acme-corp"
        output=$(aws-config-d list 2>&1)
        echo "$output" | grep -q "enabled:" &&
        echo "$output" | grep -q "acme-corp" &&
        echo "$output" | grep -q "disabled:"
    '
}

test_disable_moves_to_disabled_dir() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        echo "[profile acme-dev]" > "$HOME/.aws/config.d/acme-corp"
        aws-config-d disable acme-corp > /dev/null 2>&1
        test -f "$HOME/.aws/config.d/disabled/acme-corp" &&
        test ! -f "$HOME/.aws/config.d/acme-corp"
    '
}

test_enable_from_disabled_dir() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        echo "[profile acme-dev]" > "$HOME/.aws/config.d/acme-corp"
        aws-config-d disable acme-corp > /dev/null 2>&1
        aws-config-d enable acme-corp > /dev/null 2>&1
        test -f "$HOME/.aws/config.d/acme-corp" &&
        test ! -f "$HOME/.aws/config.d/disabled/acme-corp"
    '
}

test_enable_from_off_suffix() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        # create a .off file directly
        echo "[profile acme-dev]" > "$HOME/.aws/config.d/acme-corp.off"
        aws-config-d enable acme-corp > /dev/null 2>&1
        test -f "$HOME/.aws/config.d/acme-corp" &&
        test ! -f "$HOME/.aws/config.d/acme-corp.off"
    '
}

test_disable_prevents_00_defaults() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        if aws-config-d disable 00-defaults 2>/dev/null; then exit 1; fi
        test -f "$HOME/.aws/config.d/00-defaults"
    '
}

test_list_shows_disabled_files() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"

        echo "[profile acme-dev]" > "$HOME/.aws/config.d/acme-corp"
        aws-config-d disable acme-corp > /dev/null 2>&1
        output=$(aws-config-d list 2>&1)
        echo "$output" | grep -q "disabled/acme-corp"
    '
}

# --- example profile tests ---

test_fresh_install_copies_examples() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /tmp/out 2>&1
        # .example files should exist in config.d
        test -f "$HOME/.aws/config.d/acme-corp.example" &&
        test -f "$HOME/.aws/config.d/globex-inc.example"
    '
}

test_examples_not_copied_when_user_files_exist() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME/.aws/config.d"
        touch "$HOME/.bashrc"
        echo "[profile myorg]" > "$HOME/.aws/config.d/myorg"
        ./install.sh > /tmp/out 2>&1
        # .example files should NOT be copied
        test ! -f "$HOME/.aws/config.d/acme-corp.example" &&
        test ! -f "$HOME/.aws/config.d/globex-inc.example"
    '
}

test_examples_not_rendered_into_config() {
    docker run --rm -v "$SCRIPT_DIR":/src:ro bash:latest bash -c '
        cp -r /src /work && cd /work
        HOME=/tmp/fakehome && export HOME
        mkdir -p "$HOME"
        touch "$HOME/.bashrc"
        ./install.sh > /dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"
        # add a real profile so config is not just the header
        echo "[profile real-org]" > "$HOME/.aws/config.d/real-org"
        aws-config-d force > /dev/null 2>&1
        # .example content should not appear in rendered config
        if grep -q "acme" "$HOME/.aws/config"; then exit 1; fi
        grep -q "\[profile real-org\]" "$HOME/.aws/config"
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
echo "=== migration ==="
run_test "migrate: moves existing config to 01-migrated-config" test_migrate_existing_config
run_test "migrate: preserves config content after rebuild" test_migrate_preserves_content
run_test "migrate: rebuilt config starts with header comment" test_migrate_has_header_comment
run_test "migrate: fresh install has header comment" test_fresh_install_has_header_comment
run_test "migrate: skips when config.d already has files" test_no_migrate_when_config_d_exists

echo ""
echo "=== aws-config-d command ==="
run_test "force: rebuilds unconditionally" test_force_rebuild
run_test "force: resets drift (overwrites external edits)" test_force_resets_drift
run_test "force: works without dashes" test_force_without_dashes
run_test "help: shown by default with no args" test_help_is_default

echo ""
echo "=== disable profiles ==="
run_test "off: .off suffix excludes file from config" test_off_suffix_excluded
run_test "off: disabled/ dir excludes file from config" test_disabled_dir_excluded
run_test "off: installer creates disabled/ dir" test_installer_creates_disabled_dir
run_test "off: re-running installer updates binary" test_installer_updates_binary

echo ""
echo "=== list/enable/disable ==="
run_test "list: shows enabled and disabled sections" test_list_shows_enabled_and_disabled
run_test "disable: moves file to disabled/" test_disable_moves_to_disabled_dir
run_test "enable: restores from disabled/" test_enable_from_disabled_dir
run_test "enable: restores from .off suffix" test_enable_from_off_suffix
run_test "disable: prevents disabling 00-defaults" test_disable_prevents_00_defaults
run_test "list: shows disabled files" test_list_shows_disabled_files

echo ""
echo "=== example profiles ==="
run_test "example: fresh install copies .example files" test_fresh_install_copies_examples
run_test "example: not copied when user files exist" test_examples_not_copied_when_user_files_exist
run_test "example: .example files not rendered into config" test_examples_not_rendered_into_config

echo ""
echo "=== drift detection ==="
run_test "bash: warns on external config edit" test_bash_drift_warns_on_external_edit
run_test "bash: does not overwrite externally modified config" test_bash_drift_does_not_overwrite
run_test "bash: normal rebuild updates hash" test_bash_drift_normal_rebuild_updates_hash
run_test "fish: warns on external config edit" test_fish_drift_warns_on_external_edit

echo ""
echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
