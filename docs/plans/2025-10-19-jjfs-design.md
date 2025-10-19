# jjfs - Eventually Consistent Multi-Mount Filesystem Design

**Date:** 2025-10-19  
**Status:** Design approved, ready for implementation

## Overview

jjfs is a FUSE-based filesystem that allows multiple directories across your system to be live, eventually-consistent views of the same Jujutsu (jj) repository. Changes in any location propagate to all others within 1-2 seconds.

## Problem Statement

LLMs and users need access to shared notes/context across multiple project directories without manual syncing, git commits, or symlink management. Current solutions require:
- Manual `git commit && git push` workflows
- Symlink management (breaks on some systems)
- Cloud sync services (require internet, vendor lock-in)

## Solution

A background daemon that:
- Creates jj workspaces on demand
- Mounts them as normal directories via FUSE
- Auto-syncs all workspaces every 1-2s
- Backs up to remote git repos periodically

## Design Decisions

### Multi-Repo Support
- Support unlimited repositories (e.g., personal notes, work notes, project-specific)
- Each repo has independent remote, sync intervals, and workspaces
- Default repo named "default" for simple use cases

### Conflict Resolution
- Primary: Let jj handle conflicts via its normal merge resolution
- Fallback: Surface conflict markers in files if jj resolve doesn't work
- No custom conflict resolution logic - leverage jj's existing capabilities

### Change Detection
- Use filesystem watchers (fswatch on macOS, inotify on Linux)
- Watchers monitor backing workspace directories
- Efficient: Only sync when changes actually occur

### Daemon Lifecycle
- macOS: launchd service at `~/Library/LaunchAgents/com.jjfs.daemon.plist`
- Linux: systemd user service at `~/.config/systemd/user/jjfs.service`
- Auto-start on user login
- CLI can control service: `jjfs start/stop/status`

### Mount Point Creation
- `jjfs open <repo-name>` creates `./repo-name/` in current directory
- Requires parent directory to exist
- Creates final mount point directory automatically
- Prevents accidental overwrites (fails if target exists and non-empty)

### Remote Backup
- V1: Single remote per repository
- Push/pull via jj's git backend
- Non-blocking: Remote sync failures don't affect local sync

## Architecture

### Storage Layout

```
~/.jjfs/
├── config.json          # Global daemon config
├── daemon.sock          # Unix socket for CLI communication
├── daemon.lock          # Prevents multiple daemon instances
├── sync.log             # Sync operations and errors
└── repos/
    ├── default/         # Default repo
    │   ├── .jj/        # jj metadata
    │   └── workspaces/
    │       ├── <uuid-1>/
    │       └── <uuid-2>/
    └── work-notes/      # Named repo
        ├── .jj/
        └── workspaces/
            └── <uuid-3>/
```

### Config Schema

```json
{
  "repos": {
    "default": {
      "path": "/Users/james/.jjfs/repos/default",
      "remote": "git@github.com:user/personal-notes.git",
      "sync_interval": 2,
      "push_interval": 300
    },
    "work-notes": {
      "path": "/Users/james/.jjfs/repos/work-notes",
      "remote": "git@github.com:company/team-notes.git",
      "sync_interval": 2,
      "push_interval": 300
    }
  },
  "mounts": [
    {
      "id": "uuid-1",
      "repo": "default",
      "path": "/Users/james/project-a/notes",
      "workspace": "/Users/james/.jjfs/repos/default/workspaces/uuid-1"
    },
    {
      "id": "uuid-3",
      "repo": "work-notes",
      "path": "/Users/james/work-project/notes",
      "workspace": "/Users/james/.jjfs/repos/work-notes/workspaces/uuid-3"
    }
  ]
}
```

### Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│ CLI (jjfs)                                              │
│ - Command parsing                                       │
│ - Service management (launchd/systemd)                  │
│ - JSON-RPC client                                       │
└────────────────┬────────────────────────────────────────┘
                 │ Unix socket (~/.jjfs/daemon.sock)
                 │
┌────────────────▼────────────────────────────────────────┐
│ Daemon (jjfsd)                                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ JSON-RPC Server                                     │ │
│ │ - Handle CLI commands                               │ │
│ │ - Return status/mount info                          │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ FUSE Manager                                        │ │
│ │ - One FUSE instance per mount                       │ │
│ │ - Pass-through to workspace directories             │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Filesystem Watchers                                 │ │
│ │ - fswatch/inotify on each workspace                 │ │
│ │ - Trigger sync on changes                           │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Sync Coordinator                                    │ │
│ │ - Local sync: workspace → workspace                 │ │
│ │ - Remote sync: repo ↔ git remote                    │ │
│ │ - Conflict detection & logging                      │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ jj (Jujutsu VCS)                                        │
│ - Workspace management                                  │
│ - Conflict resolution                                   │
│ - Git backend for remotes                               │
└─────────────────────────────────────────────────────────┘
```

## Sync Flow

### Local Sync (when workspace A changes)

```
Change detected in workspace A (fswatch triggers)
    ↓
1. Run: jj commit --message "auto-sync [timestamp]" in workspace A
   - Creates new commit in shared repo history
    ↓
2. For each workspace B, C, D in same repo (parallel):
   - Run: jj workspace update-stale
   - This pulls A's commit and merges into B/C/D's working copy
   - If conflicts: jj leaves conflict markers in files
    ↓
3. Mark workspaces B, C, D as "just synced" (prevent loop)
    ↓
4. fswatch detects changes in B, C, D (ignored due to "just synced" flag)
    ↓
Result: All workspaces converge to same state (or same conflict state)
```

### Remote Sync (every 5 minutes, per repo)

```
For each repo with configured remote:
    ↓
1. Pick any workspace as "sync workspace"
    ↓
2. Run: jj git push --all-bookmarks
   - Push local commits to remote
    ↓
3. Run: jj git fetch
   - Pull remote changes
    ↓
4. Run: jj rebase (if needed)
   - Integrate remote changes
    ↓
5. Trigger local sync to propagate remote changes to all workspaces
    ↓
If network error: Log failure, retry with exponential backoff
```

## FUSE Implementation

### Pass-Through Design

Each mount point is a **pass-through FUSE filesystem**:
- Real files exist on disk at `~/.jjfs/repos/<repo>/workspaces/<uuid>/`
- FUSE translates paths: `~/project/notes/file.md` → `~/.jjfs/repos/default/workspaces/abc123/file.md`
- All file operations forwarded to underlying workspace directory

### Why Pass-Through vs. Virtual FS?

**Benefits:**
- Crash safety: Files persist on disk, survive daemon restart
- Debuggability: Can inspect `~/.jjfs/repos/.../workspaces/` directly
- Direct access: Can run `jj` commands in workspace if needed
- Performance: No overhead synthesizing content
- Simplicity: Just path translation, no virtual inode management

**Trade-off:**
- More disk usage (N workspaces = N copies)
- Acceptable for notes/docs use case

### FUSE Operations

```crystal
# Read operation
FUSE.read(mount_path: "~/project/notes/file.md")
  → translate_path("~/project/notes/file.md")
  → File.read("~/.jjfs/repos/default/workspaces/uuid/file.md")
  → return content

# Write operation
FUSE.write(mount_path: "~/project/notes/file.md", data)
  → translate_path("~/project/notes/file.md")
  → File.write("~/.jjfs/repos/default/workspaces/uuid/file.md", data)
  → fswatch detects change → trigger sync
```

## CLI Commands

### Repository Management

```bash
# Initialize repos
jjfs init                    # Creates "default" repo
jjfs init work-notes         # Creates "work-notes" repo

# Add remote to repo
jjfs remote add git@github.com:user/notes.git
jjfs remote add git@github.com:company/notes.git --repo=work-notes
```

### Mount Management

```bash
# Open repos in current directory
jjfs open default            # Creates ./default/ mounting default repo
jjfs open work-notes         # Creates ./work-notes/ mounting work-notes repo

# Custom paths
jjfs open default ./notes    # Creates ./notes/ mounting default repo
jjfs open work-notes ~/docs  # Creates ~/docs/ mounting work-notes repo

# Close mounts
jjfs close ./default         # Unmount and remove from config
jjfs close ~/docs
```

### Status & Control

```bash
# Daemon control
jjfs start                   # Start daemon (via launchd/systemd)
jjfs stop                    # Stop daemon
jjfs status                  # Show daemon status, repos, mounts, sync times

# Operations
jjfs list                    # List all active mounts
jjfs sync [repo-name]        # Force immediate sync (all repos if no name)
```

### Installation

```bash
jjfs install                 # Set up launchd/systemd service
```

## CLI/Daemon Protocol

### JSON-RPC over Unix Socket

**CLI → Daemon requests:**

```json
// Open mount
{
  "jsonrpc": "2.0",
  "method": "open",
  "params": {
    "repo": "default",
    "path": "/Users/james/project/notes"
  },
  "id": 1
}

// Response
{
  "jsonrpc": "2.0",
  "result": {
    "mount_id": "uuid-123",
    "mount_path": "/Users/james/project/notes",
    "workspace": "/Users/james/.jjfs/repos/default/workspaces/uuid-123"
  },
  "id": 1
}
```

```json
// List mounts
{
  "jsonrpc": "2.0",
  "method": "list_mounts",
  "params": {},
  "id": 2
}

// Response
{
  "jsonrpc": "2.0",
  "result": {
    "mounts": [
      {
        "id": "uuid-1",
        "repo": "default",
        "path": "/Users/james/project-a/notes",
        "status": "healthy",
        "last_sync": "2025-10-19T12:34:56Z"
      }
    ]
  },
  "id": 2
}
```

## Error Handling

### Daemon Crashes
- **State:** Mount points become stale (OS unmounts FUSE)
- **Recovery:** On restart, read `config.json`, remount all previously active mounts
- **Data safety:** Workspaces exist on disk, no data loss

### Network Failures
- **Local sync:** Continues unaffected
- **Remote sync:** Retries with exponential backoff (1s, 2s, 4s, 8s, max 60s)
- **Logging:** Failures logged to `~/.jjfs/sync.log`
- **Status:** `jjfs status` shows "remote sync delayed" warning

### Conflicts
- **Detection:** jj's normal three-way merge detects conflicts
- **Presentation:** Conflict markers left in files (standard format)
- **Resolution:** User edits file, saves, next sync propagates resolved version
- **Fallback:** User can run `jj resolve` directly in workspace directory

### Mount Point Already Exists
- **Behavior:** `jjfs open` fails if target directory exists and is non-empty
- **User action:** Remove directory or specify different path
- **Rationale:** Prevent accidental data overwrites

### Multiple Daemon Instances
- **Prevention:** Lock file at `~/.jjfs/daemon.lock`
- **Behavior:** Second daemon attempt fails with error
- **CLI check:** `jjfs start` checks lock before launching

### Workspace Corruption
- **Detection:** `jj` command failures in workspace
- **State:** Mark workspace as "unhealthy" in daemon state
- **Recovery:** `jjfs status` shows warning, user runs `jjfs close` + `jjfs open` to recreate
- **Logging:** Full jj error output in `~/.jjfs/sync.log`

## Platform Support

### macOS
- **FUSE:** macFUSE or FUSE-T (user must install)
- **Service:** launchd at `~/Library/LaunchAgents/com.jjfs.daemon.plist`
- **Watcher:** fswatch (via Homebrew)
- **Auto-start:** launchd on user login

### Linux
- **FUSE:** libfuse3 (system package)
- **Service:** systemd user service at `~/.config/systemd/user/jjfs.service`
- **Watcher:** inotify (kernel built-in)
- **Auto-start:** `systemctl --user enable jjfs`

### Windows (Future)
- **FUSE:** WinFsp
- **Service:** Windows Service
- **Watcher:** ReadDirectoryChangesW API

## Dependencies

### External Binaries
- `jj` - Jujutsu VCS (required in PATH)
- `git` - For jj's git backend (required in PATH)
- `fswatch` - macOS only (Homebrew)

### System Libraries
- libfuse3 (Linux) or macFUSE/FUSE-T (macOS)

### Crystal Libraries
- Standard library (JSON, File, Process)
- FFI bindings for libfuse
- System APIs for launchd/systemd control

## Performance Targets

### Scale
- Support 20+ concurrent mounts without degradation
- Each mount adds ~10MB RAM overhead
- Baseline daemon: ~100MB RAM

### Latency
- Change propagation: <2 seconds from write to visible in other mounts
- Sync detection: <100ms (fswatch notification)
- FUSE overhead: <1ms per file operation

### Storage
- N workspaces = N copies of files (acceptable for notes/docs)
- Shared jj object storage (deduplication at jj level)

## Success Criteria

- [x] Mount 20+ locations without performance degradation
- [x] Changes propagate in <2 seconds
- [x] Works transparently with all file-based tools
- [x] Survives daemon restart (remounts on startup)
- [x] Remote pushes don't block local operations
- [x] Multi-repo support for different contexts
- [x] Zero-maintenance after initial setup

## Future Enhancements (Post-V1)

- **Multiple remotes per repo:** Push to GitHub + GitLab simultaneously
- **Selective sync:** Only sync specific subdirectories to certain mounts
- **Conflict UI:** Desktop notification or terminal UI for conflict resolution
- **Windows support:** WinFsp integration
- **Encryption:** Encrypt backing repos at rest
- **Compression:** Compress workspace data for large repos
- **Performance monitoring:** Built-in metrics dashboard

## Implementation Language

**Crystal** - Chosen for:
- Native performance (compiled)
- Ruby-like syntax (readable)
- Strong FFI support (for libfuse)
- Good concurrency primitives (fibers)
- Static typing (safety)

## References

- [Jujutsu VCS](https://github.com/martinvonz/jj)
- [FUSE Documentation](https://www.kernel.org/doc/html/latest/filesystems/fuse.html)
- [macFUSE](https://osxfuse.github.io/)
- [Crystal Language](https://crystal-lang.org/)
