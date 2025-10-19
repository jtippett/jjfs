#!/usr/bin/env bash
set -euo pipefail

# jjfs release script - commit-based workflow
# Usage: ./scripts/release.sh [commit-sha]
# Example: ./scripts/release.sh abc123
# Default: Uses current HEAD

COMMIT="${1:-HEAD}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="${REPO_ROOT}/homebrew-tap"

cd "$REPO_ROOT"

# Resolve commit to full SHA
COMMIT_SHA=$(git rev-parse "$COMMIT")
SHORT_SHA=$(git rev-parse --short "$COMMIT")

echo "🚀 Releasing jjfs from commit ${SHORT_SHA}"
echo

# Check commit exists remotely
if ! git branch -r --contains "$COMMIT_SHA" | grep -q origin; then
  echo "❌ Error: Commit ${SHORT_SHA} not pushed to origin"
  echo "   Push with: git push origin master"
  exit 1
fi

# Get current version from shard.yml
CURRENT_VERSION=$(grep '^version:' shard.yml | awk '{print $2}')
echo "📌 Current version: ${CURRENT_VERSION}"

# Increment patch version
IFS='.' read -r major minor patch <<< "$CURRENT_VERSION"
NEW_VERSION="${major}.${minor}.$((patch + 1))"

echo "📝 New version: ${NEW_VERSION}"
read -p "   Use this version? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
  read -p "   Enter version: " NEW_VERSION
fi

echo
echo "✅ Will release:"
echo "   Version: ${NEW_VERSION}"
echo "   Commit:  ${COMMIT_SHA}"
echo "   Short:   ${SHORT_SHA}"
echo

# Update shard.yml
echo "📝 Updating shard.yml..."
sed -i.bak "s/^version: .*/version: ${NEW_VERSION}/" shard.yml
rm shard.yml.bak

# Update src/jjfs.cr
echo "📝 Updating src/jjfs.cr..."
sed -i.bak "s/VERSION = \".*\"/VERSION = \"${NEW_VERSION}\"/" src/jjfs.cr
rm src/jjfs.cr.bak

# Commit version bump
echo "📝 Committing version bump..."
git add shard.yml src/jjfs.cr
git commit -m "chore: bump version to ${NEW_VERSION}"
git push origin master

# Get the new commit SHA (after version bump)
RELEASE_SHA=$(git rev-parse HEAD)
RELEASE_SHORT=$(git rev-parse --short HEAD)

echo
echo "📦 Updating Homebrew formula..."

# Update formula
FORMULA="${TAP_DIR}/Formula/jjfs.rb"

# Update version line
sed -i.bak "s/^  version \".*\"/  version \"${NEW_VERSION}\"/" "$FORMULA"

# Update url to use git with revision
cat > "${FORMULA}.tmp" << EOF
class Jjfs < Formula
  desc "Eventually consistent multi-mount filesystem using Jujutsu"
  homepage "https://github.com/jtippett/jjfs"
  version "${NEW_VERSION}"
  url "https://github.com/jtippett/jjfs.git",
      revision: "${RELEASE_SHA}"
  license "MIT"

  depends_on "crystal"
  depends_on "jj"

  on_macos do
    depends_on "fswatch"
  end

  on_linux do
    depends_on "bindfs"
  end

  def install
    # Create bin directory for build
    mkdir_p "bin"

    # Build both binaries
    system "crystal", "build", "src/jjfs.cr", "-o", "bin/jjfs", "--release"
    system "crystal", "build", "src/jjfsd.cr", "-o", "bin/jjfsd", "--release"

    # Install binaries
    bin.install "bin/jjfs"
    bin.install "bin/jjfsd"

    # Install templates for service installation
    prefix.install "templates"

    # Install documentation
    doc.install "README.md"
    doc.install "CHANGELOG.md"
    doc.install "docs/user-guide.md"
  end

  def post_install
    ohai "jjfs installed successfully!"
  end

  def caveats
    s = <<~EOS
      To get started:
        1. Install bindfs: brew install --cask macfuse && brew install gromgit/fuse/bindfs-mac
        2. Install the daemon service: jjfs install
        3. Initialize a repo: jjfs init
        4. Open a mount: jjfs open default

      Note: bindfs requires macFUSE to be installed separately.

      After upgrading, restart the daemon to use the new version:
        jjfs stop
        jjfs start

      For more information, see:
        #{doc}/README.md
        #{doc}/user-guide.md
    EOS

    on_linux do
      s = <<~EOS
        To get started:
          1. Install the daemon service: jjfs install
          2. Initialize a repo: jjfs init
          3. Open a mount: jjfs open default

        For more information, see:
          #{doc}/README.md
          #{doc}/user-guide.md
      EOS
    end

    s
  end

  test do
    # Test that binaries run and show version
    assert_match "jjfs v${NEW_VERSION}", shell_output("#{bin}/jjfs 2>&1")

    # Test init command (in temporary directory)
    system bin/"jjfs", "init", "test-repo"
    assert_predicate testpath/".jjfs/repos/test-repo", :exist?
    assert_predicate testpath/".jjfs/config.json", :exist?
  end
end
EOF

mv "${FORMULA}.tmp" "$FORMULA"
rm -f "${FORMULA}.bak"

# Commit and push formula
cd "$TAP_DIR"
git add Formula/jjfs.rb
git commit -m "chore: release ${NEW_VERSION} (${RELEASE_SHORT})"
git push origin master

cd "$REPO_ROOT"

echo
echo "✅ Release ${NEW_VERSION} complete!"
echo
echo "   Main repo:    ${RELEASE_SHA}"
echo "   Formula:      commit-based, no SHA256 needed"
echo
echo "📋 Test installation:"
echo "   brew uninstall jjfs 2>/dev/null || true"
echo "   brew untap jtippett/jjfs"
echo "   brew install jtippett/jjfs"
echo
