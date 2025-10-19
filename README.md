# jjfs - Eventually Consistent Multi-Mount Filesystem

FUSE-based filesystem that allows multiple directories to be live, eventually-consistent views of the same Jujutsu repository.

## Features

- **Multi-mount:** Mount same repo in unlimited locations
- **Eventually consistent:** Changes propagate automatically (<2s)
- **Zero maintenance:** Auto-syncs, auto-starts on login
- **Remote backup:** Push/pull to GitHub/GitLab
- **Cross-platform:** macOS and Linux

## Status

**Version:** 0.1.0  
**Status:** Ready for production use

jjfs provides a stable foundation for multi-location file synchronization using Jujutsu's workspace feature. The sync engine has been tested with multiple concurrent mounts and handles conflicts gracefully.

## Installation

### Requirements

- Crystal 1.10+
- Jujutsu (`jj`) - [Install guide](https://github.com/martinvonz/jj#installation)
- bindfs (FUSE filesystem for pass-through mounting)
- **macOS:** fswatch (`brew install fswatch bindfs`)
- **Linux:** inotify (built-in), bindfs (`apt-get install bindfs` or `yum install bindfs`)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/jjfs.git
cd jjfs

# Install dependencies (if any)
shards install

# Build release binaries
crystal build src/jjfs.cr -o bin/jjfs --release
crystal build src/jjfsd.cr -o bin/jjfsd --release

# Install to system (optional)
sudo cp bin/jjfs /usr/local/bin/
sudo cp bin/jjfsd /usr/local/bin/
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
# Initialize a repo
jjfs init my-notes

# Open the repo in multiple locations
jjfs open my-notes ~/Documents/notes
jjfs open my-notes ~/Desktop/quick-notes

# Work in either location - changes sync automatically!
echo "Hello world" > ~/Documents/notes/hello.txt
# Wait ~2 seconds
cat ~/Desktop/quick-notes/hello.txt
# Output: Hello world

# Add a remote for backup (optional)
jjfs remote add git@github.com:user/my-notes.git --repo=my-notes

# View all mounts
jjfs list

# Close a mount when done
jjfs close ~/Desktop/quick-notes
```

## Usage

### Commands

```bash
jjfs init [name]              # Initialize a repo (default: "default")
jjfs open <repo> [path]       # Open repo at path (default: ./<repo>)
jjfs close <path>             # Close mount at path
jjfs list                     # List all mounts
jjfs status                   # Show daemon status
jjfs start                    # Start daemon
jjfs stop                     # Stop daemon
jjfs sync [repo]              # Force sync (default: all repos)
jjfs remote add <url>         # Add remote for backup
jjfs install                  # Install system service
```

### How It Works

1. **Each mount is a jj workspace** - Uses jujutsu's built-in workspace feature
2. **File changes trigger commits** - fswatch/inotify detects changes, commits them
3. **Workspaces auto-update** - `jj workspace update-stale` propagates changes
4. **Remotes sync periodically** - Pushes/pulls every 5 minutes (configurable)
5. **Conflicts are preserved** - Jujutsu conflict markers appear in files

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

### Changes not syncing
```bash
# Check daemon is running
jjfs status

# Check daemon logs
tail -f ~/.jjfs/sync.log

# Force manual sync
jjfs sync repo-name
```

### Conflicts
If you edit the same file in multiple mounts simultaneously, jj will create conflict markers:
```
<<<<<<< Conflict 1 of 1
%%%%%%% Changes from abc123
Content from mount A
+++++++ Contents of def456
Content from mount B
>>>>>>> Conflict 1 of 1 ends
```

Resolve by editing the file to keep the desired content, then save.

## Architecture

- **CLI (`jjfs`)**: User-facing commands
- **Daemon (`jjfsd`)**: Long-running process managing mounts and sync
- **RPC**: JSON-RPC over Unix socket for CLI-daemon communication
- **Mount Manager**: Creates/destroys jj workspaces and bindfs mounts
- **Sync Coordinator**: Watches for changes, commits, and propagates to other workspaces
- **Remote Syncer**: Periodically pushes/pulls to git remotes

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
