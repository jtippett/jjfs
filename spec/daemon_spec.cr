require "./spec_helper"
require "../src/daemon"
require "file_utils"

describe JJFS::Daemon do
  it "starts and creates socket" do
    tmp_dir = File.tempname("jjfs_test")
    storage = JJFS::Storage.new(tmp_dir)
    storage.ensure_directories

    daemon = JJFS::Daemon.new(storage)

    # Start in fiber to test non-blocking
    spawn { daemon.start }
    sleep 0.1

    File.exists?(storage.socket_path).should be_true
    File.exists?(storage.lock_path).should be_true

    daemon.stop
    FileUtils.rm_rf(tmp_dir)
  end
end
