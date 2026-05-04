# GitHub CLI (`gh`) Installation

> Install and authenticate the GitHub CLI on macOS, Linux, and Windows.

## What is `gh`?

The official GitHub command-line tool. Lets you work with issues, pull requests, releases, and repositories directly from the terminal — without leaving the shell or opening the browser.

## Installation

### macOS

**Homebrew (recommended):**

```bash
brew install gh
```

**MacPorts:**

```bash
sudo port install gh
```

**Upgrade:**

```bash
brew upgrade gh
```

### Linux

**Debian / Ubuntu:**

```bash
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh -y
```

**Fedora / RHEL / CentOS:**

```bash
sudo dnf install 'dnf-command(config-manager)'
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install gh --repo gh-cli
```

**Arch Linux:**

```bash
sudo pacman -S github-cli
```

### Windows

**winget:**

```powershell
winget install --id GitHub.cli
```

**Scoop:**

```powershell
scoop install gh
```

**Chocolatey:**

```powershell
choco install gh
```

## Authentication

After installation, authenticate with your GitHub account:

```bash
gh auth login
```

Follow the interactive prompts:

1. **What account do you want to log into?** → `GitHub.com`
2. **What is your preferred protocol for Git operations?** → `HTTPS` (or `SSH` if you use SSH keys)
3. **Authenticate Git with your GitHub credentials?** → `Y`
4. **How would you like to authenticate?** → `Login with a web browser` (recommended)

Copy the one-time code shown in the terminal, press Enter, and complete the auth flow in the browser.

### Verify auth

```bash
gh auth status
```

Expected output:

```
github.com
  ✓ Logged in to github.com as your-username
  ✓ Git operations for github.com configured to use https protocol.
  ✓ Token: gho_************************************
```

## Common commands

| Command | Description |
|---------|-------------|
| `gh repo clone owner/repo` | Clone a repository |
| `gh repo view --web` | Open current repo in browser |
| `gh pr create` | Create a pull request |
| `gh pr list` | List PRs in current repo |
| `gh pr checkout 123` | Check out PR #123 locally |
| `gh pr view 123 --web` | Open PR #123 in browser |
| `gh issue create` | Create an issue |
| `gh issue list` | List issues |
| `gh run list` | List recent workflow runs |
| `gh run watch` | Watch a workflow run live |

## Troubleshooting

**`gh: command not found`** → Restart your terminal after installation, or check that the install path is in your `$PATH`.

**Auth token expired** → Run `gh auth refresh` or `gh auth login` again.

**Wrong account** → Use `gh auth switch` to change between logged-in accounts.

## References

- Official site: https://cli.github.com
- Manual: https://cli.github.com/manual
- Repo: https://github.com/cli/cli
