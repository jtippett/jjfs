# Changelog

All notable changes to jjfs will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-10-19

### Added

#### Core Functionality
- **Multi-mount support**: Mount the same Jujutsu repository in multiple filesystem locations simultaneously
- **Automatic synchronization**: Changes propagate between mounts within ~2 seconds
- **Filesystem watching**: Automatic change detection using fswatch (macOS) or inotify (Linux)
- **Conflict handling**: Leverages Jujutsu's conflict resolution with visible conflict markers

#### CLI Commands
- `jjfs init [name]` - Initialize a new repository
- `jjfs open <repo> [path]` - Open/mount a repository at a filesystem location
- `jjfs close <path>` - Close/unmount a repository
- `jjfs list` - List all active mounts
- `jjfs status` - Show daemon status and statistics
- `jjfs start` - Start the daemon manually
- `jjfs stop` - Stop the daemon
- `jjfs sync [repo]` - Force synchronization (all repos or specific repo)
- `jjfs remote add <url>` - Add a git remote for backup/sharing
- `jjfs install` - Install system service (launchd/systemd)

#### Daemon Features
- **Long-running daemon** (`jjfsd`) for managing mounts and synchronization
- **JSON-RPC over Unix socket** for CLI-daemon communication
- **Automatic startup** via launchd (macOS) or systemd (Linux)
- **Graceful shutdown** handling with proper cleanup
- **PID-based locking** to prevent multiple daemon instances

#### Sync Engine
- **Workspace-based architecture**: Each mount is a Jujutsu workspace
- **Automatic commits**: File changes trigger automatic commits with timestamps
- **Cross-workspace sync**: Changes propagate to all mounts of the same repo
- **Loop prevention**: Smart detection to prevent infinite sync loops
- **Remote sync**: Periodic push/pull to git remotes (configurable interval)

#### System Integration
- **Service installation**: Automatic setup for launchd (macOS) and systemd (Linux)
- **Mount via bindfs**: FUSE-based pass-through mounting for file access
- **Configuration management**: JSON-based config in `~/.jjfs/config.json`
- **Logging**: Structured logging to `~/.jjfs/sync.log`

#### Testing
- **Unit tests**: Full test coverage for core components
- **Integration tests**: End-to-end testing of sync flows
- **Multiple mount tests**: Verification of multi-mount synchronization
- **Conflict handling tests**: Validation of jj conflict resolution
- **Graceful handling**: Tests skip bindfs-dependent tests when bindfs unavailable

#### Documentation
- **Comprehensive README**: Installation, quick start, usage examples
- **User Guide**: Detailed workflows, troubleshooting, and FAQ
- **Architecture documentation**: Technical design and implementation details
- **Implementation plan**: Step-by-step development guide

### Technical Details

#### Dependencies
- Crystal 1.10+
- Jujutsu (jj) CLI
- bindfs (FUSE filesystem)
- fswatch (macOS) or inotify (Linux)

#### Architecture
- **Storage layer**: Manages repos and configuration
- **Mount manager**: Creates/destroys jj workspaces and bindfs mounts
- **Sync coordinator**: Watches for changes and propagates between workspaces
- **Remote syncer**: Handles git push/pull operations
- **RPC server**: JSON-RPC interface for CLI communication

#### File Locations
- Config: `~/.jjfs/config.json`
- Repos: `~/.jjfs/repos/<name>/`
- Workspaces: `~/.jjfs/repos/<name>/workspaces/<uuid>/`
- Socket: `~/.jjfs/daemon.sock`
- Lock: `~/.jjfs/daemon.lock`
- Logs: `~/.jjfs/sync.log`, `~/.jjfs/daemon.log`, `~/.jjfs/daemon.error.log`

### Known Limitations

- **bindfs required**: Currently depends on external bindfs for FUSE mounting
- **Local-only mounts**: Network filesystem mounts not supported
- **Single-user**: Designed for single-user scenarios
- **Text-optimized**: Best performance with text files; binary files supported but less optimal
- **Manual remote setup**: Initial git remote setup requires manual configuration on each device

### Future Improvements

Potential enhancements for future versions:
- Native FUSE implementation (remove bindfs dependency)
- Improved conflict resolution UI
- Real-time sync status indicators
- Web UI for management
- Better multi-device setup workflow
- Performance optimizations for large repositories

## [Unreleased]

No unreleased changes yet.

---

## Release Notes

### Version 0.1.0 - Initial Release

This is the first public release of jjfs, providing a stable foundation for multi-location file synchronization using Jujutsu workspaces. The core functionality has been thoroughly tested and is ready for production use.

**Highlights:**
- 🚀 Fast local synchronization (<2s between mounts)
- 🔄 Automatic conflict resolution via Jujutsu
- 📦 Optional git remote backup
- 🖥️ Cross-platform (macOS and Linux)
- ⚡ Zero-maintenance operation with automatic startup

**Getting Started:**
```bash
# Install dependencies
brew install jujutsu fswatch bindfs  # macOS
# or appropriate package manager for Linux

# Build and install
crystal build src/jjfs.cr -o bin/jjfs --release
crystal build src/jjfsd.cr -o bin/jjfsd --release
sudo cp bin/jjfs* /usr/local/bin/

# Setup
jjfs install
jjfs init my-notes
jjfs open my-notes ~/Documents/notes
```

**Testing:**
All tests pass on macOS 14.x with Crystal 1.10.1 and Jujutsu 0.21.0.

**Feedback Welcome:**
This is an initial release. Please report any issues or suggestions on GitHub!

[0.1.0]: https://github.com/yourusername/jjfs/releases/tag/v0.1.0
