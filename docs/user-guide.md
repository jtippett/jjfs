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
   This configures jjfsd to start automatically on login (using launchd on macOS or systemd on Linux).

4. **Verify daemon is running:**
   ```bash
   jjfs status
   # Output: Daemon: running
   ```

### Your First Repo

Let's create a simple note-taking setup:

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
- Each "repo" is a Jujutsu repository stored in `~/.jjfs/repos/<name>/`
- Each "mount" is a Jujutsu workspace for that repo
- Changes in any mount are automatically committed and synced to other mounts
- Sync happens within ~2 seconds of file changes

**Key concepts:**
- **Repo**: A Jujutsu repository (you can have multiple: notes, code, docs, etc.)
- **Mount**: A filesystem location where you can access/edit files
- **Workspace**: The underlying jj workspace (managed automatically)
- **Sync**: The process of propagating changes between mounts

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

# Daemon will automatically push to GitHub every 5 minutes
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

# Changes will sync via GitHub automatically
```

**Note:** For proper multi-device sync, you need to manually set up the git repo on each device. jjfs handles the push/pull automatically once configured.

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

# Each repo is independent - changes don't cross repos
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

**Use case:** Test code in one location while keeping stable version in another.

```bash
jjfs init my-project
jjfs open my-project ~/dev/stable
jjfs open my-project ~/dev/experimental

# Work in experimental branch
cd ~/dev/experimental
# ... make risky changes ...

# If they work, they're automatically in ~/dev/stable too
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
- `path`: Location of the jj repository (managed by jjfs)
- `remote`: Git remote URL for push/pull (optional)
- `sync_interval`: Seconds between file change detection (default: 2)
- `push_interval`: Seconds between remote syncs (default: 300)

**Mount settings:**
- `id`: Unique workspace identifier (UUID)
- `repo`: Name of the repo this mount belongs to
- `path`: Filesystem location where files are accessible
- `workspace`: Internal jj workspace path

### Modifying Configuration

**Don't edit the config file directly while the daemon is running.** Instead:

```bash
# Stop daemon
jjfs stop

# Edit ~/.jjfs/config.json
nano ~/.jjfs/config.json

# Restart daemon
jjfs start
```

Or use the CLI commands which handle this automatically:
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

Since jjfs uses jj under the hood, you can use jj commands directly:

```bash
cd ~/.jjfs/repos/notes
jj log  # View commit history
jj show  # View latest changes
```

### Managing Conflicts

If you edit the same line in the same file from multiple mounts simultaneously, jj creates conflict markers:

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
2. Edit to keep the desired content (removing conflict markers)
3. Save the file
4. jj automatically creates a new revision with the resolution

### Inspecting Workspaces

List all workspaces for a repo:
```bash
cd ~/.jjfs/repos/notes
jj workspace list
```

### Backup and Recovery

**Backup your repos:**
```bash
# All repo data is in ~/.jjfs/repos/
tar -czf jjfs-backup.tar.gz ~/.jjfs/repos/
```

**Restore from backup:**
```bash
tar -xzf jjfs-backup.tar.gz -C ~/
jjfs start
```

### Using with Git Directly

You can interact with the underlying git repository:

```bash
cd ~/.jjfs/repos/notes
jj git export  # Export jj commits to git
git log  # View git history
git push origin main  # Manual push (daemon does this automatically)
```

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
# Verify bindfs is working
mount | grep bindfs

# Check if workspace exists
ls ~/.jjfs/repos/<repo>/workspaces/

# Try unmounting and remounting
jjfs close /path/to/mount
jjfs open <repo> /path/to/mount
```

**Can't mount: "directory not empty":**
```bash
# jjfs requires mount point to be empty
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

**Changes not syncing:**
```bash
# Check daemon status
jjfs status

# Check if watcher is running
ps aux | grep fswatch  # macOS
ps aux | grep inotifywait  # Linux

# Check sync logs
tail -f ~/.jjfs/sync.log

# Force manual sync
jjfs sync <repo>
```

**Sync is slow:**
```bash
# Check system resources
top  # High CPU?
df -h  # Disk full?

# Reduce number of mounts if too many
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

**Push/pull failing:**
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

### Q: How is this different from Dropbox/iCloud?

**A:** jjfs is designed for local multi-mount synchronization with version control. Unlike cloud services:
- Syncs between local directories instantly (<2s)
- Full version history via Jujutsu
- Works offline (no cloud required)
- Optional git remote for backup/sharing
- Designed for text files and code

### Q: Can I use this with binary files?

**A:** Yes, but jjfs (and Jujutsu) are optimized for text files. Binary files work but:
- Take more storage space
- Don't merge well (conflicts harder to resolve)
- Version history less useful

### Q: What happens if I edit the same file in two mounts at once?

**A:** Jujutsu creates conflict markers in the file. You'll see both versions and can choose which to keep or merge them manually.

### Q: Can I have multiple repos?

**A:** Yes! Create as many repos as you want:
```bash
jjfs init work
jjfs init personal
jjfs init code
```

Each repo is independent.

### Q: How much disk space does this use?

**A:** Each mount is a lightweight jj workspace (~50KB overhead). The repo stores all history, which depends on your file sizes and edit frequency. Use `du -sh ~/.jjfs/repos/<name>` to check.

### Q: Can I use this for large files or many files?

**A:** jjfs works best with:
- Small to medium files (< 10MB each)
- Moderate file counts (< 10,000 files)
- Text-based content

For large binary files or massive directories, consider specialized solutions.

### Q: Is my data safe?

**A:** 
- All changes are versioned in Jujutsu (can rollback)
- Use remotes for off-machine backup
- jjfs doesn't delete data (only creates new versions)
- Regular backups recommended: `tar -czf backup.tar.gz ~/.jjfs/repos/`

### Q: Can I use this in production?

**A:** jjfs v0.1.0 is stable for personal use. For production:
- Test thoroughly with your workflow
- Always configure remote backups
- Monitor daemon logs
- Have a backup strategy

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

**A:** No. jjfs is for local mounts only. For network sync:
1. Use jjfs locally on each machine
2. Configure git remotes
3. Daemon syncs via git push/pull

### Q: What if the daemon crashes while I'm editing?

**A:** Your files are safe in the workspace. When daemon restarts:
1. Uncommitted changes remain in the workspace
2. Next file change triggers a commit
3. Sync resumes normally

No data is lost.

## Getting Help

- **Issues/Bugs**: Open an issue on GitHub
- **Questions**: Check this guide and FAQ first
- **Logs**: Always include logs from `~/.jjfs/sync.log` when reporting issues

## Best Practices

1. **Start small**: Begin with one repo and a few mounts
2. **Use remotes**: Always configure git remotes for important data
3. **Monitor logs**: Occasionally check `~/.jjfs/sync.log` for errors
4. **Clean up**: Close mounts you're not using
5. **Backup**: Regular backups of `~/.jjfs/repos/`
6. **Text files**: Works best with text-based content
7. **Don't edit workspaces directly**: Always use mount points, not `~/.jjfs/repos/*/workspaces/`

## What's Next?

Now that you understand jjfs, try:
- Setting up your own note-taking workflow
- Syncing a project across multiple directories
- Configuring remote backup to GitHub
- Creating multiple repos for different purposes

Happy syncing!
