require "../spec_helper"
require "../../src/commands/init"
require "file_utils"

describe JJFS::Commands::Init do
  it "creates repo with default name" do
    tmp_dir = File.tempname("jjfs_test")
    storage = JJFS::Storage.new(tmp_dir)

    cmd = JJFS::Commands::Init.new(storage, "default")
    cmd.execute

    Dir.exists?(storage.repo_path("default")).should be_true
    Dir.exists?(storage.workspaces_dir("default")).should be_true
    storage.config.repos.has_key?("default").should be_true

    FileUtils.rm_rf(tmp_dir)
  end
end
