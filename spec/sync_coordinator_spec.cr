require "./spec_helper"
require "../src/sync_coordinator"
require "file_utils"

describe JJFS::SyncCoordinator do
  it "initializes with storage" do
    tmp_dir = File.tempname("jjfs_test")
    storage = JJFS::Storage.new(tmp_dir)

    coordinator = JJFS::SyncCoordinator.new(storage)
    coordinator.should_not be_nil

    FileUtils.rm_rf(tmp_dir)
  end

  it "starts and stops watchers" do
    tmp_dir = File.tempname("jjfs_test")
    storage = JJFS::Storage.new(tmp_dir)
    storage.ensure_directories

    coordinator = JJFS::SyncCoordinator.new(storage)
    coordinator.start
    coordinator.stop

    FileUtils.rm_rf(tmp_dir)
  end

  it "adds watcher for new mount" do
    tmp_dir = File.tempname("jjfs_test")
    storage = JJFS::Storage.new(tmp_dir)
    storage.ensure_directories

    coordinator = JJFS::SyncCoordinator.new(storage)
    coordinator.start

    # Create a mock mount
    workspace_path = File.join(tmp_dir, "workspace")
    Dir.mkdir_p(workspace_path)

    mount = JJFS::MountConfig.new(
      id: "test-id",
      repo: "test-repo",
      path: "/tmp/mount",
      workspace: workspace_path
    )

    coordinator.add_mount(mount)
    coordinator.stop

    FileUtils.rm_rf(tmp_dir)
  end
end
