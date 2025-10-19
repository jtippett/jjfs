#!/usr/bin/env bash
set -euo pipefail

# Test jjfs locally without Homebrew installation
# Usage: ./scripts/test-local.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "🔨 Building jjfs and jjfsd..."
crystal build src/jjfs.cr -o bin/jjfs
crystal build src/jjfsd.cr -o bin/jjfsd

echo
echo "✅ Build complete!"
echo
echo "📋 Testing locally:"
echo

# Stop any running daemon (via launchd)
echo "Stopping launchd daemon (if running)..."
jjfs stop 2>/dev/null || true

# Clean up any stale files
echo "Cleaning up stale files..."
rm -f ~/.jjfs/daemon.sock ~/.jjfs/daemon.lock

# Start local daemon in background
echo "Starting local daemon..."
./bin/jjfsd &
DAEMON_PID=$!

sleep 2

# Test status
echo
echo "Testing status command..."
./bin/jjfs status

echo
echo "Testing init command..."
./bin/jjfs init test-local

echo
echo "Listing mounts..."
./bin/jjfs list

echo
echo "✅ Local testing complete!"
echo
echo "Daemon running with PID: $DAEMON_PID"
echo "Stop with: kill $DAEMON_PID"
echo
echo "To use locally:"
echo "  export PATH=\"$REPO_ROOT/bin:\$PATH\""
echo "  jjfs status"
echo
