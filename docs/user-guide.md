# jjfs User Guide

This guide covers common workflows, best practices, and troubleshooting for jjfs.

## Table of Contents

- [Getting Started](#getting-started)
- [Common Workflows](#common-workflows)
- [Configuration](#configuration)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

## Getting Started

### First-Time Setup

1. **Install dependencies:**
   ```bash
   # macOS
   brew install jujutsu fswatch bindfs
   
   # Linux (Ubuntu/Debian)
   sudo apt-get install bindfs inotify-tools
   # Install jj from https://github.com/martinvonz/jj#installation
   ```

2. **Build and install jjfs:**
   ```bash
   cd jjfs
   crystal build src/jjfs.cr -o bin/jjfs --release
   crystal build src/jjfsd.cr -o bin/jjfsd --release
   sudo cp bin/jjfs /usr/local/bin/
   sudo cp bin/jjfsd /usr/local/bin/
   ```

3. **Install the system service:**
   ```bash
   jjfs install
   ```
   This configures jjfsd to start automatically on login using launchd on macOS or systemd on Linux.

4. **Verify the daemon runs:**
   ```bash
   jjfs status
   # Output: Daemon: running
   ```

### Git Repository Integration

jjfs detects when you mount inside an existing git repository. It offers to add the mount directory to your `.gitignore` file to prevent synced content from polluting your git repository.

```bash
cd ~/my-project  # An existing git repo
jjfs open notes ./my-notes

# Output:
# ⚠️  Warning: You're opening a mount inside a git repository.
#    To avoid polluting this repo with synced content, add to .gitignore?
#    Add '/my-notes' to ~/my-project/.gitignore? [Y/n]
# > y
# ✓ Added '/my-notes' to .gitignore
```

This feature keeps your jjfs mounts separate from your existing git repositories.

### Your First Repo

Create a simple note-taking setup:

```bash
# Initialize a repo called "notes"
jjfs init notes

# Open it in your Documents folder
jjfs open notes ~/Documents/notes

# Create a file
echo "# My Notes" > ~/Documents/notes/README.md

# Open the same repo in another location
jjfs open notes ~/Desktop/quick-notes

# The file appears automatically!
cat ~/Desktop/quick-notes/README.md
# Output: # My Notes
```

### Understanding the Basics

**How jjfs works:**
- jjfs stores each "repo" as a Jujutsu repository in `~/.jjfs/repos/<name>/`
- Each "mount" creates a Jujutsu workspace for that repo
- jjfs automatically commits and syncs changes in any mount to other mounts
- Sync happens within 2 seconds of file changes

**Key concepts:**
- **Repo**: A Jujutsu repository (you can create multiple: notes, code, docs)
- **Mount**: A filesystem location where you access and edit files
- **Workspace**: The underlying jj workspace (jjfs manages this automatically)
- **Sync**: The process that propagates changes between mounts

## Common Workflows

### Workflow 1: Personal Notes Across Multiple Locations

**Use case:** You want quick access to notes from both your Documents folder and Desktop.

```bash
# Setup
jjfs init notes
jjfs open notes ~/Documents/notes
jjfs open notes ~/Desktop/quick-notes

# Daily use
echo "Meeting notes..." > ~/Documents/notes/meetings/2025-10-19.md
# File immediately appears in ~/Desktop/quick-notes/meetings/2025-10-19.md

# Cleanup when done with desktop access
jjfs close ~/Desktop/quick-notes
```

### Workflow 2: Syncing Notes Across Devices

**Use case:** Keep notes synchronized between your laptop and desktop via GitHub.

**On Device 1 (Laptop):**
```bash
# Initialize and add remote
jjfs init notes
jjfs remote add git@github.com:yourusername/notes.git --repo=notes

# Create initial content
jjfs open notes ~/Documents/notes
echo "# Shared Notes" > ~/Documents/notes/README.md

# Daemon automatically pushes to GitHub every 5 minutes
# Or force immediate push:
jjfs sync notes
```

**On Device 2 (Desktop):**
```bash
# First, manually clone the repo
mkdir -p ~/.jjfs/repos
git clone git@github.com:yourusername/notes.git ~/.jjfs/repos/notes
cd ~/.jjfs/repos/notes
jj git import  # Import git history into jj

# Then configure jjfs
jjfs remote add git@github.com:yourusername/notes.git --repo=notes
jjfs open notes ~/Documents/notes

# Changes sync via GitHub automatically
```

**Note:** You must manually set up the git repo on each device for multi-device sync. Once configured, jjfs handles push and pull automatically.

### Workflow 3: Multiple Projects

**Use case:** Separate repositories for work, personal, and code projects.

```bash
# Create separate repos
jjfs init work-notes
jjfs init personal
jjfs init code-snippets

# Mount each in its own location
jjfs open work-notes ~/Work/notes
jjfs open personal ~/Personal/journal
jjfs open code-snippets ~/Code/snippets

# View all mounts
jjfs list

# Each repo operates independently—changes stay within their repo
```

### Workflow 4: Temporary Project View

**Use case:** You need quick access to files for a specific task, then want to unmount.

```bash
# Mount temporarily
jjfs open notes ~/temp-notes-access

# Do your work
cd ~/temp-notes-access
# ... edit files ...

# Unmount when done
jjfs close ~/temp-notes-access
```

### Workflow 5: Development Workflow

**Use case:** Test code in one location while keeping a stable version in another.

```bash
jjfs init my-project
jjfs open my-project ~/dev/stable
jjfs open my-project ~/dev/experimental

# Work in experimental branch
cd ~/dev/experimental
# ... make risky changes ...

# Your changes appear automatically in ~/dev/stable
# If you break something, jj's conflict resolution helps you fix it
```

## Configuration

### Config File Location

jjfs stores its configuration in `~/.jjfs/config.json`.

### Config Structure

```json
{
  "repos": {
    "notes": {
      "path": "/Users/you/.jjfs/repos/notes",
      "remote": "git@github.com:user/notes.git",
      "sync_interval": 2,
      "push_interval": 300
    }
  },
  "mounts": [
    {
      "id": "a1b2c3d4-...",
      "repo": "notes",
      "path": "/Users/you/Documents/notes",
      "workspace": "/Users/you/.jjfs/repos/notes/workspaces/a1b2c3d4-..."
    }
  ]
}
```

### Configuration Options

**Repo settings:**
- `path`: Location of the jj repository (jjfs manages this)
- `remote`: Git remote URL for push and pull (optional)
- `sync_interval`: Seconds between file change detection (default: 2)
- `push_interval`: Seconds between remote syncs (default: 300)

**Mount settings:**
- `id`: Unique workspace identifier (UUID)
- `repo`: Name of the repo this mount belongs to
- `path`: Filesystem location where files are accessible
- `workspace`: Internal jj workspace path

### Modifying Configuration

Stop the daemon before you edit the config file directly:

```bash
# Stop daemon
jjfs stop

# Edit ~/.jjfs/config.json
nano ~/.jjfs/config.json

# Restart daemon
jjfs start
```

Use CLI commands to modify configuration automatically:
```bash
jjfs remote add <url> --repo=<name>
jjfs open <repo> <path>
jjfs close <path>
```

## Advanced Usage

### Manual Sync Control

Force an immediate sync (useful for testing):
```bash
# Sync all repos
jjfs sync

# Sync specific repo
jjfs sync notes
```

### Viewing Jujutsu History

jjfs uses jj under the hood, so you can use jj commands directly:

```bash
cd ~/.jjfs/repos/notes
jj log  # View commit history
jj show  # View latest changes
```

### Managing Conflicts

jj creates conflict markers when you edit the same line in the same file from multiple mounts simultaneously:

```
<<<<<<< Conflict 1 of 1
%%%%%%% Changes from revision abc123
This is version A
+++++++ Contents of revision def456
This is version B
>>>>>>> Conflict 1 of 1 ends
```

**To resolve:**
1. Open the file in your editor
2. Edit to keep the desired content and remove conflict markers
3. Save the file
4. jj automatically creates a new revision with your resolution

### Inspecting Workspaces

List all workspaces for a repo:
```bash
cd ~/.jjfs/repos/notes
jj workspace list
```

### Backup and Recovery

**Backup your repos:**
```bash
# All repo data lives in ~/.jjfs/repos/
tar -czf jjfs-backup.tar.gz ~/.jjfs/repos/
```

**Restore from backup:**
```bash
tar -xzf jjfs-backup.tar.gz -C ~/
jjfs start
```

### Using with Git Directly

Interact with the underlying git repository directly:

```bash
cd ~/.jjfs/repos/notes
jj git export  # Export jj commits to git
git log  # View git history
git push origin main  # Manual push (daemon does this automatically)
```

### Mounting Inside Git Repositories

jjfs detects when you mount a directory inside an existing git repository and offers to add the mount to `.gitignore`:

```bash
cd ~/my-git-project
jjfs open notes ./project-notes
# jjfs offers to add '/project-notes' to .gitignore
```

This prevents your jjfs-synced content from being tracked by the outer git repository. If you decline the automatic addition, add the mount directory to `.gitignore` manually to avoid confusion.

## Troubleshooting

### Daemon Issues

**Daemon won't start:**
```bash
# Check if already running
jjfs status

# Look for stale lock file
cat ~/.jjfs/daemon.lock
ps aux | grep jjfsd  # Check if process exists

# Remove stale lock if process is dead
rm ~/.jjfs/daemon.lock
jjfs start
```

**Daemon crashes or stops:**
```bash
# Check daemon logs
tail -f ~/.jjfs/sync.log

# Check system logs (macOS)
tail -f ~/.jjfs/daemon.log
tail -f ~/.jjfs/daemon.error.log

# Restart daemon
jjfs stop
jjfs start
```

### Mount Issues

**Mount appears empty:**
```bash
# Verify bindfs works
mount | grep bindfs

# Check if workspace exists
ls ~/.jjfs/repos/<repo>/workspaces/

# Try unmounting and remounting
jjfs close /path/to/mount
jjfs open <repo> /path/to/mount
```

**Mount fails with "directory not empty":**
```bash
# jjfs requires an empty mount point
# Either:
# 1. Use a different directory
# 2. Or move files out and try again
mv /path/to/mount /path/to/mount.backup
jjfs open <repo> /path/to/mount
```

**Can't unmount:**
```bash
# Check for open files
lsof | grep /path/to/mount

# Force unmount (macOS)
sudo umount -f /path/to/mount

# Force unmount (Linux)
sudo fusermount -u /path/to/mount

# Clean up jjfs state
jjfs close /path/to/mount
```

### Sync Issues

**Changes fail to sync:**
```bash
# Check daemon status
jjfs status

# Check if watcher runs
ps aux | grep fswatch  # macOS
ps aux | grep inotifywait  # Linux

# Check sync logs
tail -f ~/.jjfs/sync.log

# Force manual sync
jjfs sync <repo>
```

**Sync runs slow:**
```bash
# Check system resources
top  # High CPU?
df -h  # Disk full?

# Reduce mounts if you have too many
jjfs list
jjfs close /path/to/unnecessary/mount
```

### Permission Issues

**Permission denied errors:**
```bash
# Check ownership
ls -la ~/.jjfs/

# Fix permissions
chmod -R u+rw ~/.jjfs/
```

### Remote Sync Issues

**Push or pull fails:**
```bash
# Test git access manually
cd ~/.jjfs/repos/<repo>
git fetch origin

# Check remote URL
jj git remote -v

# Update remote if wrong
jj git remote remove origin
jjfs remote add <correct-url> --repo=<name>
```

## FAQ

### Q: How does this differ from Dropbox or iCloud?

**A:** jjfs synchronizes local directories instantly with full version control. Unlike cloud services:
- Syncs between local directories in under 2 seconds
- Maintains full version history via Jujutsu
- Works offline (no cloud required)
- Supports optional git remote for backup and sharing
- Optimizes for text files and code

### Q: Can I use this with binary files?

**A:** Yes, but jjfs (and Jujutsu) optimize for text files. Binary files work but:
- Consume more storage space
- Merge poorly (conflicts are harder to resolve)
- Provide less useful version history

### Q: What happens if I edit the same file in two mounts at once?

**A:** Jujutsu creates conflict markers in the file. You see both versions and can choose which to keep or merge them manually.

### Q: Can I have multiple repos?

**A:** Yes! Create as many repos as you want:
```bash
jjfs init work
jjfs init personal
jjfs init code
```

Each repo operates independently.

### Q: How much disk space does this use?

**A:** Each mount creates a lightweight jj workspace with approximately 50KB overhead. The repo stores all history, which depends on your file sizes and edit frequency. Check usage with `du -sh ~/.jjfs/repos/<name>`.

### Q: Can I use this for large files or many files?

**A:** jjfs works best with:
- Small to medium files (under 10MB each)
- Moderate file counts (under 10,000 files)
- Text-based content

For large binary files or massive directories, consider specialized solutions.

### Q: Is my data safe?

**A:** 
- Jujutsu versions all changes (you can rollback)
- Remotes provide off-machine backup
- jjfs creates new versions instead of deleting data
- Regular backups recommended: `tar -czf backup.tar.gz ~/.jjfs/repos/`

### Q: Can I use this in production?

**A:** jjfs v0.1.0 is stable for personal use. For production:
- Test thoroughly with your workflow
- Always configure remote backups
- Monitor daemon logs
- Maintain a backup strategy

### Q: How do I uninstall?

**A:**
```bash
# Stop and remove service
jjfs stop
launchctl unload ~/Library/LaunchAgents/com.jjfs.daemon.plist  # macOS
systemctl --user disable jjfs  # Linux

# Remove binaries
sudo rm /usr/local/bin/jjfs /usr/local/bin/jjfsd

# Remove data (optional - this deletes all your repos!)
rm -rf ~/.jjfs/
```

### Q: Does this work over a network?

**A:** No. jjfs creates local mounts only. For network sync:
1. Use jjfs locally on each machine
2. Configure git remotes
3. Daemon syncs via git push and pull

### Q: What if the daemon crashes while I'm editing?

**A:** Your files remain safe in the workspace. When the daemon restarts:
1. Uncommitted changes remain in the workspace
2. The next file change triggers a commit
3. Sync resumes normally

jjfs loses no data.

## Getting Help

- **Issues or Bugs**: Open an issue on GitHub
- **Questions**: Check this guide and FAQ first
- **Logs**: Always include logs from `~/.jjfs/sync.log` when you report issues

## Best Practices

1. **Start small**: Begin with one repo and a few mounts
2. **Use remotes**: Always configure git remotes for important data
3. **Monitor logs**: Occasionally check `~/.jjfs/sync.log` for errors
4. **Clean up**: Close mounts you're not using
5. **Backup**: Back up `~/.jjfs/repos/` regularly
6. **Text files**: Use jjfs primarily for text-based content
7. **Use mount points**: Always edit via mount points, never directly in `~/.jjfs/repos/*/workspaces/`

## What's Next?

Now that you understand jjfs, try:
- Setting up your own note-taking workflow
- Syncing a project across multiple directories
- Configuring remote backup to GitHub
- Creating multiple repos for different purposes

Happy syncing!
