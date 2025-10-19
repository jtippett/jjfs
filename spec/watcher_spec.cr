require "./spec_helper"
require "../src/watcher"
require "file_utils"

describe JJFS::Watcher do
  it "detects file changes" do
    tmp_dir = File.tempname("jjfs_test")
    Dir.mkdir_p(tmp_dir)

    changed = false
    changed_path = ""
    watcher = JJFS::Watcher.new(tmp_dir) do |path|
      changed = true
      changed_path = path
    end

    spawn { watcher.start }
    sleep 0.2  # Give watcher time to start

    test_file = File.join(tmp_dir, "test.txt")
    File.write(test_file, "content")
    sleep 0.5  # Give watcher time to detect change

    changed.should be_true
    changed_path.should_not be_empty

    watcher.stop
    FileUtils.rm_rf(tmp_dir)
  end

  it "detects multiple file changes" do
    tmp_dir = File.tempname("jjfs_test")
    Dir.mkdir_p(tmp_dir)

    changes = [] of String
    watcher = JJFS::Watcher.new(tmp_dir) do |path|
      changes << path
    end

    spawn { watcher.start }
    sleep 0.2

    File.write(File.join(tmp_dir, "file1.txt"), "content1")
    sleep 0.3
    File.write(File.join(tmp_dir, "file2.txt"), "content2")
    sleep 0.3

    changes.size.should be >= 2

    watcher.stop
    FileUtils.rm_rf(tmp_dir)
  end

  it "stops watching when stop is called" do
    tmp_dir = File.tempname("jjfs_test")
    Dir.mkdir_p(tmp_dir)

    changes_before_stop = 0
    changes_after_stop = 0
    stopped = false

    watcher = JJFS::Watcher.new(tmp_dir) do |path|
      if stopped
        changes_after_stop += 1
      else
        changes_before_stop += 1
      end
    end

    spawn { watcher.start }
    sleep 0.2

    File.write(File.join(tmp_dir, "before_stop.txt"), "content")
    sleep 0.4

    watcher.stop
    stopped = true
    sleep 0.2

    # This should not be detected
    File.write(File.join(tmp_dir, "after_stop.txt"), "content")
    sleep 0.4

    changes_before_stop.should be >= 1
    changes_after_stop.should eq(0)

    FileUtils.rm_rf(tmp_dir)
  end
end
