require "./spec_helper"
require "file_utils"

describe JJFS::Config do
  it "initializes with default values" do
    config = JJFS::Config.new
    config.repos.should be_empty
    config.mounts.should be_empty
  end

  it "serializes to JSON" do
    config = JJFS::Config.new
    json = config.to_json
    json.should contain("repos")
    json.should contain("mounts")
  end
end

describe JJFS::Storage do
  it "creates storage directory structure" do
    tmp_dir = File.tempname("jjfs_test")

    storage = JJFS::Storage.new(tmp_dir)
    storage.ensure_directories

    Dir.exists?(File.join(tmp_dir, "repos")).should be_true
    File.exists?(storage.config_path).should be_true

    FileUtils.rm_rf(tmp_dir)
  end
end
