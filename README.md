# aws-config-d

Split `~/.aws/config` into one file per organization. Concatenate on shell start. No dependencies.

## Why this exists

If you work with more than two AWS organizations, your `~/.aws/config` is a mess. SSO profiles, session blocks, and account IDs from unrelated clients all live in one file. You scroll past dozens of profiles to find the one you need, and every `aws configure sso` run dumps more into the pile.

The AWS CLI doesn't support `config.d/` natively. There's been [an open feature request](https://github.com/aws/aws-cli/issues/9036) since March 2022 asking for exactly this. The SDK team showed initial interest, then explained it would need to ship across all AWS SDKs simultaneously. PRs have been rejected. Nothing has shipped. Nothing is on the roadmap.

This tool exists because that upstream change isn't coming.

## How it works

You keep per-organization files in `~/.aws/config.d/`:

```
~/.aws/config.d/
  00-defaults      # shared settings, default region
  acme-corp        # Acme Corp profiles + SSO session
  globex-inc       # Globex Inc profiles + SSO session
  old-client.off   # disabled — .off suffix skips it
  disabled/        # park files here to stop rendering without deleting
```

A shell hook calls `aws-config-d auto` at the start of each session. If any source file is newer than `~/.aws/config`, it concatenates them all and writes the result:

```
aws: rebuilt ~/.aws/config from config.d/
```

If nothing changed, it does nothing. No overhead.

A SHA-256 hash tracks what was last generated. If something else edits `~/.aws/config` directly (like `aws configure sso`), the next rebuild detects the drift and warns you instead of silently overwriting.

## Install

One line:

```bash
bash -c 'tmp=$(mktemp -d) && git clone --depth 1 https://github.com/awesome-foundation/aws-config-d.git "$tmp/aws-config-d" && "$tmp/aws-config-d/install.sh" && rm -rf "$tmp"'
```

Or clone and run:

```bash
git clone git@github.com:awesome-foundation/aws-config-d.git
cd aws-config-d
./install.sh
```

Here's what that does:

1. Creates `~/.aws/config.d/` with a `00-defaults` header and a `disabled/` folder
2. Migrates your existing `~/.aws/config` into `config.d/01-migrated-config` (if present and config.d is empty)
3. Installs the `aws-config-d` command to `~/.local/bin` (override with `INSTALL_DIR`)
4. Adds the auto-rebuild hook to your shell's RC file (bash, zsh, and fish all supported)
5. Builds `~/.aws/config` from the parts

Re-running the installer is safe. It updates the binary, skips hooks that are already installed, and won't touch your config files.

### Shells supported

| Shell | RC file |
|-------|---------|
| bash  | `~/.bashrc` |
| zsh   | `~/.zshrc` |
| fish  | `~/.config/fish/config.fish` |

### Manual install

If you'd rather do it yourself:

1. `mkdir -p ~/.aws/config.d`
2. `cp bin/aws-config-d ~/.local/bin/`
3. Add the contents of the appropriate snippet file (`config.bash.snippet`, `config.zsh.snippet`, or `config.fish.snippet`) to your RC file
4. `aws-config-d force`

## Usage

### Add a new organization

Drop a file in `~/.aws/config.d/`:

```ini
# ~/.aws/config.d/my-new-client
[profile my-new-client-dev]
sso_session=my-new-client
sso_account_id=123456789012
sso_role_name=DeveloperAccess
region=eu-west-1

[sso-session my-new-client]
sso_start_url=https://my-new-client.awsapps.com/start/
sso_region=eu-west-1
sso_registration_scopes=sso:account:access
```

Open a new shell. Done.

### Enable and disable profiles

```bash
aws-config-d disable acme-corp    # moves to disabled/
aws-config-d enable acme-corp     # moves back
aws-config-d list                 # shows what's on and off
aws-config-d rm old-client        # permanently deletes
```

You can also disable manually: rename with `.off` or move to `disabled/`. The `enable` command understands both. `disable` always moves to `disabled/`.

### Force a rebuild

```bash
aws-config-d force
```

Rebuilds unconditionally and resets the drift hash.

### File ordering

Files concatenate in lexicographic order. Prefix with numbers to control it (`00-defaults` always goes first).

### Drift detection

If `~/.aws/config` gets edited outside of `config.d/` (by `aws configure sso`, by hand, by another tool), the next auto-rebuild catches it:

```
aws: WARNING — ~/.aws/config was modified outside of config.d/
aws: possibly by 'aws configure sso' or manual editing.
aws: reconcile changes into ~/.aws/config.d/ then run:
aws:   aws-config-d force
```

Copy the relevant changes into the right file under `config.d/`, then `aws-config-d force`.

## Testing

42 tests across bash, zsh, and fish, each running in isolated Docker containers. Requires Docker.

```bash
./test.sh
```

Covers install hooks, rebuild triggers, idempotency, migration, drift detection, enable/disable/rm commands, and installer upgrades.

## Limitations

- This is a workaround. The AWS CLI doesn't support `config.d/` natively; this tool concatenates files.
- `aws configure sso` edits `~/.aws/config` directly. That triggers a drift warning. Reconcile into `config.d/` and force-rebuild.
- `~/.aws/credentials` is not managed. Same pattern would work with a `credentials.d/` if you need it.

## License

[MPL-2.0](LICENSE) — you can use, modify, and distribute this tool freely. Modifications to the source files must remain open and include attribution.
