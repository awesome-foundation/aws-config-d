# aws-cli-config-d

Split your `~/.aws/config` into separate files per AWS organization.

## The problem

When working with multiple AWS organizations using SSO, `~/.aws/config` becomes a long, hard-to-navigate file mixing profiles from unrelated clients. The AWS CLI doesn't support `include` directives or a `config.d/` pattern natively.

## How it works

Instead of maintaining a single `~/.aws/config`, you keep per-organization files in `~/.aws/config.d/`:

```
~/.aws/config.d/
  00-defaults     # default profile, shared settings
  acme-corp       # all Acme Corp profiles + SSO session
  globex-inc      # all Globex Inc profiles + SSO session
```

A shell hook runs at the start of each session and calls `aws-config-d auto`, which checks if any file in `config.d/` is newer than `~/.aws/config`. If so, it concatenates them all into `~/.aws/config` and prints a message:

```
aws: rebuilt ~/.aws/config from config.d/
```

If nothing changed, it does nothing.

A SHA-256 hash of the generated config is stored so that external modifications (e.g., `aws configure sso` editing `~/.aws/config` directly) are detected before being overwritten. If drift is found, you'll see a warning instead of a rebuild.

## Supported shells

| Shell | Snippet file | RC file |
|-------|-------------|---------|
| bash  | `config.bash.snippet` | `~/.bashrc` |
| zsh   | `config.zsh.snippet` | `~/.zshrc` |
| fish  | `config.fish.snippet` | `~/.config/fish/config.fish` |

## Quick install

```bash
bash -c 'tmp=$(mktemp -d) && git clone --depth 1 https://github.com/awesome-foundation/aws-cli-config-d.git "$tmp/aws-cli-config-d" && "$tmp/aws-cli-config-d/install.sh" && rm -rf "$tmp"'
```

Or clone and run manually:

```bash
git clone git@github.com:awesome-foundation/aws-cli-config-d.git
cd aws-cli-config-d
./install.sh
```

The installer will:
1. Create `~/.aws/config.d/` with a `00-defaults` header file
2. If `~/.aws/config` already exists and `config.d/` is empty, migrate it to `~/.aws/config.d/01-migrated-config` so nothing is lost
3. Install the `aws-config-d` command to `~/.local/bin` (override with `INSTALL_DIR`)
4. Detect your shell(s) and add the auto-rebuild hook to the appropriate RC file(s)
5. Build `~/.aws/config` from the parts

If you had an existing config, you'll be prompted to split it into per-organization files at your convenience.

The installer checks for all three shells and installs hooks for each one it finds, so if you use multiple shells they'll all work.

### Manual

1. Create `~/.aws/config.d/` and move your profiles into per-organization files:

```bash
mkdir -p ~/.aws/config.d
```

2. Copy the `aws-config-d` script to somewhere on your `PATH`:

```bash
cp bin/aws-config-d ~/.local/bin/aws-config-d
```

3. Add the contents of the appropriate snippet file to your shell's RC file:

   - **bash**: add `config.bash.snippet` to `~/.bashrc`
   - **zsh**: add `config.zsh.snippet` to `~/.zshrc`
   - **fish**: add `config.fish.snippet` to `~/.config/fish/config.fish`

4. Rebuild the config:

```bash
aws-config-d --force
```

## Usage

### Adding a new organization

Create a new file in `~/.aws/config.d/` with the organization's profiles:

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

The next time you open a shell, the config will be rebuilt automatically.

### Ordering

Files are concatenated in lexicographic order. Use numeric prefixes to control ordering (e.g., `00-defaults` runs first).

### Forcing a rebuild

```bash
aws-config-d --force
```

This rebuilds `~/.aws/config` unconditionally and resets the drift hash.

### Drift detection

If `~/.aws/config` is modified outside of `config.d/` (e.g., by `aws configure sso` or manual editing), the next auto-rebuild will detect the mismatch and warn you instead of overwriting:

```
aws: WARNING — ~/.aws/config was modified outside of config.d/
aws: possibly by 'aws configure sso' or manual editing.
aws: reconcile changes into ~/.aws/config.d/ then run:
aws:   aws-config-d --force
```

Copy the relevant changes into the appropriate file under `config.d/`, then run `aws-config-d --force` to rebuild.

## Testing

Tests run each shell in an isolated Docker container to verify the install and rebuild hooks work correctly. Requires Docker.

```bash
./test.sh
```

This runs 22 tests across bash, zsh, and fish covering:
- Hook installation into the correct RC file
- Config rebuild when a source file is touched
- No rebuild when nothing changed
- Idempotent installs (running twice doesn't duplicate the hook)
- Generated config contains all profiles from all source files
- Migration of existing `~/.aws/config`
- `aws-config-d --force` unconditional rebuild
- Drift detection when config is modified externally

Docker images used: `bash:latest`, `zshusers/zsh:latest`, `purefish/docker-fish:latest`.

## Limitations

- The AWS CLI does not support `config.d/` natively. This is a workaround that concatenates files.
- Editing `~/.aws/config` directly (e.g., via `aws configure sso`) will trigger a drift warning on the next rebuild. Reconcile changes into `config.d/` and run `aws-config-d --force`.
- `~/.aws/credentials` is not managed by this tool. You could apply the same pattern with a `credentials.d/` directory if needed.
