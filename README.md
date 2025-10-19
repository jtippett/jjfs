# jjfs - Eventually Consistent Multi-Mount Filesystem

NFS-based filesystem that mounts multiple directories as live, eventually-consistent views of the same Jujutsu repository.

## Features

- **Multi-mount:** Mount the same repo in unlimited locations
- **Eventually consistent:** Changes propagate automatically (<2s)
- **Zero maintenance:** Auto-syncs and auto-starts on login
- **Remote backup:** Push and pull to GitHub or GitLab
- **Cross-platform:** Runs on macOS and Linux
- **Git-aware:** Detects git repos and offers to update .gitignore
- **No external dependencies:** Built-in NFS server, no FUSE or kernel extensions required
- **Easy repo management:** Import existing git repos or create new jj repos with simple commands

## Status

**Version:** 0.2.0
**Status:** Production ready (with known NFS unmount caveat on macOS)

jjfs provides a stable foundation for multi-location file synchronization using Jujutsu's workspace feature. The sync engine handles multiple concurrent mounts and resolves conflicts gracefully.

## Installation

### via Homebrew (macOS/Linux)

```bash
brew install jtippett/jjfs/jjfs
```

This installs both `jjfs` and `jjfsd`. Note: On macOS, you'll need to install bindfs separately (see caveats after installation).

Alternatively, tap first then install:
```bash
brew tap jtippett/jjfs
brew install jjfs
```

### Build from Source

#### Requirements

- Crystal 1.10+
- Rust toolchain (for building jjfs-nfs)
- Jujutsu (`jj`) - [Install guide](https://github.com/martinvonz/jj#installation)
- **macOS:** fswatch (`brew install fswatch`)
- **Linux:** inotify (built-in)

#### Build Steps

```bash
# Clone the repository
git clone https://github.com/jtippett/jjfs.git
cd jjfs

# Install dependencies (if any)
shards install

# Build Rust NFS server
cd jjfs-nfs
cargo build --release
cp target/release/jjfs-nfs ../bin/
cd ..

# Build Crystal binaries
crystal build src/jjfs.cr -o bin/jjfs --release
crystal build src/jjfsd.cr -o bin/jjfsd --release

# Install to system (optional)
sudo cp bin/jjfs /usr/local/bin/
sudo cp bin/jjfsd /usr/local/bin/
sudo cp bin/jjfs-nfs /usr/local/bin/
```

### Setup

```bash
# Install system service (starts daemon automatically)
jjfs install

# Or start daemon manually
jjfsd &

# Initialize default repo
jjfs init
```

## Quick Start

```bash
# Create a new repo
jjfs new my-notes

# Or import an existing git repo
jjfs import https://github.com/user/notes.git

# View available repos
jjfs repos

# Open the repo in multiple locations (requires sudo password for NFS mount)
jjfs open my-notes ~/Documents/notes
jjfs open my-notes ~/Desktop/quick-notes

# Work in either location - changes sync automatically!
echo "Hello world" > ~/Documents/notes/hello.txt
# Wait ~2 seconds
cat ~/Desktop/quick-notes/hello.txt
# Output: Hello world

# View all mounts with status
jjfs list

# Close a mount when done
jjfs close ~/Desktop/quick-notes
```

## Usage

### Commands

**Repo Management:**
```bash
jjfs new <name>                    # Create new jj repo
jjfs import <git-url> [name]       # Import existing git repo
jjfs repos                         # List all available repos
jjfs init [name]                   # Initialize a repo (default: "default")
```

**Mount Management:**
```bash
jjfs open <repo> [path]            # Open repo at path (default: ./<repo>)
jjfs close <path>                  # Close mount at path
jjfs list                          # List all mounts with status
```

**Daemon:**
```bash
jjfs status                        # Show daemon status
jjfs start                         # Start daemon
jjfs stop                          # Stop daemon
```

**Other:**
```bash
jjfs sync [repo]                   # Force sync (default: all repos)
jjfs remote add <url> [--repo=name]
jjfs install                       # Install system service
```

### How It Works

jjfs builds on Jujutsu's workspace feature to synchronize files across mounts. Each mount represents a jj workspace. When you change files, fswatch or inotify detects the changes and commits them. The system then runs `jj workspace update-stale` to propagate changes across workspaces. Every 5 minutes (configurable), the system pushes and pulls to remote repositories. Jujutsu preserves conflicts by inserting conflict markers into files. When you mount inside a git repo, jjfs detects this and offers to add the mount to .gitignore.

### Configuration

Config file: `~/.jjfs/config.json`

```json
{
  "repos": {
    "my-notes": {
      "path": "/Users/you/.jjfs/repos/my-notes",
      "remote": "git@github.com:user/my-notes.git",
      "sync_interval": 2,
      "push_interval": 300
    }
  },
  "mounts": [
    {
      "id": "workspace-id",
      "repo": "my-notes",
      "path": "/Users/you/Documents/notes",
      "workspace": "/Users/you/.jjfs/repos/my-notes/workspaces/workspace-id"
    }
  ]
}
```

## Use Cases

### Sync Notes Across Devices
Keep your notes synchronized on multiple devices with automatic backup to GitHub:
```bash
# On device 1
jjfs init notes
jjfs remote add git@github.com:user/notes.git
jjfs open notes ~/Documents/notes

# On device 2 (after cloning the git repo to ~/.jjfs/repos/notes)
jjfs open notes ~/Documents/notes
```

### Multiple Views of Same Project
Work on the same codebase from different directories:
```bash
jjfs init project
jjfs open project ~/work/project-stable
jjfs open project ~/work/project-experimental

# Changes in either location sync immediately
```

### Desktop + Mobile Workflow
Keep a quick-access folder in sync with your main workspace:
```bash
jjfs init todos
jjfs open todos ~/Documents/todos
jjfs open todos ~/Desktop/quick-todos
```

## Troubleshooting

### Daemon won't start
```bash
# Check if already running
jjfs status

# Check lock file
cat ~/.jjfs/daemon.lock

# Remove stale lock if needed
rm ~/.jjfs/daemon.lock
```

### Mount appears empty
```bash
# Check if bindfs is installed
which bindfs

# Check mount status
mount | grep bindfs

# Try remounting
jjfs close /path/to/mount
jjfs open repo-name /path/to/mount
```

### Changes fail to sync
```bash
# Check daemon is running
jjfs status

# Check daemon logs
tail -f ~/.jjfs/sync.log

# Force manual sync
jjfs sync repo-name
```

### Conflicts
When you edit the same file in multiple mounts simultaneously, jj creates conflict markers:
```
<<<<<<< Conflict 1 of 1
%%%%%%% Changes from abc123
Content from mount A
+++++++ Contents of def456
Content from mount B
>>>>>>> Conflict 1 of 1 ends
```

Resolve conflicts by editing the file to keep the desired content, then save.

## Architecture

jjfs consists of six main components:
- **CLI (`jjfs`)**: Handles user-facing commands
- **Daemon (`jjfsd`)**: Runs as a long-running process managing mounts and sync
- **RPC**: Uses JSON-RPC over Unix socket for CLI-daemon communication
- **Mount Manager**: Creates and destroys jj workspaces and bindfs mounts
- **Sync Coordinator**: Watches for changes, commits them, and propagates to other workspaces
- **Remote Syncer**: Pushes and pulls to git remotes periodically

## Development

```bash
# Run tests
crystal spec

# Run integration tests (requires bindfs)
crystal spec spec/integration_spec.cr

# Build in debug mode
crystal build src/jjfs.cr -o bin/jjfs
crystal build src/jjfsd.cr -o bin/jjfsd

# Run daemon in foreground for debugging
./bin/jjfsd
```

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.

## Documentation

- [User Guide](docs/user-guide.md) - Detailed workflows and examples
- [Implementation Plan](docs/plans/2025-10-19-jjfs-implementation.md) - Technical design

## Credits

Built with:
- [Jujutsu](https://github.com/martinvonz/jj) - Version control system
- [Crystal](https://crystal-lang.org/) - Programming language
- [bindfs](https://bindfs.org/) - FUSE filesystem for pass-through mounting
