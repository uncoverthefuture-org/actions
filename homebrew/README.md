# Homebrew Tap for UActions

## Installation

### Option 1: Install directly
```bash
brew install uncver/actions/uactions
```

### Option 2: Tap first, then install
```bash
brew tap uncver/actions
brew install uactions
```

## Requirements

- **Node.js** 18+ - `brew install node`
- **Podman** - `brew install podman`

## Usage

```bash
# Initialize UActions
uactions init --domain yourdomain.pc

# Deploy an app
uactions deploy my-app

# Watch for changes (auto-deploy)
uactions watch

# List deployments
uactions list

# Show status
uactions status
```

## Uninstallation

```bash
brew uninstall uactions
brew untap uncver/actions
```

## Development

To work on the formula locally:
```bash
cd homebrew
brew install --build-from-source ./uactions.rb
```

## Issues

Report issues at: https://github.com/uncoverthefuture-org/actions/issues