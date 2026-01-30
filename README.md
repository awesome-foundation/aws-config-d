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

A shell hook runs at the start of each session and checks if any file in `config.d/` is newer than `~/.aws/config`. If so, it concatenates them all into `~/.aws/config` and prints a message:

```
aws: rebuilt ~/.aws/config from config.d/
```

If nothing changed, it does nothing.

## Supported shells

| Shell | Snippet file | RC file |
|-------|-------------|---------|
| bash  | `config.bash.snippet` | `~/.bashrc` |
| zsh   | `config.zsh.snippet` | `~/.zshrc` |
| fish  | `config.fish.snippet` | `~/.config/fish/config.fish` |

## Setup

### Automatic

```bash
./install.sh
```

This will:
1. Create `~/.aws/config.d/` with example files (won't overwrite existing ones)
2. Detect your shell(s) and add the auto-rebuild hook to the appropriate RC file(s)
3. Build `~/.aws/config` from the parts

The installer checks for all three shells and installs hooks for each one it finds, so if you use multiple shells they'll all work.

### Manual

1. Create `~/.aws/config.d/` and move your profiles into per-organization files:

```bash
mkdir -p ~/.aws/config.d
```

2. Add the contents of the appropriate snippet file to your shell's RC file:

   - **bash**: add `config.bash.snippet` to `~/.bashrc`
   - **zsh**: add `config.zsh.snippet` to `~/.zshrc`
   - **fish**: add `config.fish.snippet` to `~/.config/fish/config.fish`

3. Rebuild the config:

```bash
cat ~/.aws/config.d/* > ~/.aws/config
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

Touch any file in the directory:

```bash
touch ~/.aws/config.d/00-defaults
```

Then open a new shell session.

## Testing

Tests run each shell in an isolated Docker container to verify the install and rebuild hooks work correctly. Requires Docker.

```bash
./test.sh
```

This runs 11 tests across bash, zsh, and fish covering:
- Hook installation into the correct RC file
- Config rebuild when a source file is touched
- No rebuild when nothing changed
- Idempotent installs (running twice doesn't duplicate the hook)
- Generated config contains all profiles from all source files

Docker images used: `bash:latest`, `zshusers/zsh:latest`, `purefish/docker-fish:latest`.

## Limitations

- The AWS CLI does not support `config.d/` natively. This is a workaround that concatenates files.
- Editing `~/.aws/config` directly (e.g., via `aws configure sso`) will be overwritten on the next rebuild. Edit the source files in `config.d/` instead.
- `~/.aws/credentials` is not managed by this tool. You could apply the same pattern with a `credentials.d/` directory if needed.
