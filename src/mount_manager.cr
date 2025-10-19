require "uuid"
require "./storage"

module JJFS
  class MountManager
    def initialize(@storage : Storage)
    end

    def mount(repo_name : String, mount_path : String) : MountConfig?
      # Validate repo exists
      repo = @storage.config.repos[repo_name]?
      unless repo
        puts "Error: Repo '#{repo_name}' not found"
        return nil
      end

      # Expand and validate mount path
      full_path = File.expand_path(mount_path)
      parent = File.dirname(full_path)

      unless Dir.exists?(parent)
        puts "Error: Parent directory #{parent} does not exist"
        return nil
      end

      if Dir.exists?(full_path) && !Dir.empty?(full_path)
        puts "Error: Mount point #{full_path} exists and is not empty"
        return nil
      end

      # Create mount point
      Dir.mkdir_p(full_path)

      # Create workspace
      workspace_id = UUID.random.to_s
      workspace_path = File.join(@storage.workspaces_dir(repo_name), workspace_id)

      # Add workspace to jj repo
      Dir.cd(repo.path) do
        error_io = IO::Memory.new
        result = Process.run("jj", ["workspace", "add", workspace_path],
                           output: Process::Redirect::Pipe,
                           error: error_io)

        unless result.success?
          puts "Error: Failed to create jj workspace: #{error_io.to_s}"
          Dir.delete(full_path) if Dir.exists?(full_path)
          return nil
        end
      end

      # Mount with bindfs (pass-through)
      error_io = IO::Memory.new
      begin
        result = Process.run("bindfs", [workspace_path, full_path],
                           output: Process::Redirect::Pipe,
                           error: error_io)

        unless result.success?
          puts "Error: Failed to mount with bindfs: #{error_io.to_s}"
          return nil
        end
      rescue ex : File::NotFoundError
        puts "Error: bindfs not found. Please install bindfs:"
        puts "  macOS: brew install bindfs"
        puts "  Linux: apt-get install bindfs (or yum install bindfs)"
        return nil
      end

      # Create mount config
      mount_config = MountConfig.new(
        id: workspace_id,
        repo: repo_name,
        path: full_path,
        workspace: workspace_path
      )

      @storage.config.mounts << mount_config
      @storage.persist_config

      mount_config
    end

    def unmount(mount_path : String) : Bool
      full_path = File.expand_path(mount_path)

      mount = @storage.config.mounts.find { |m| m.path == full_path }
      unless mount
        puts "Error: No mount found at #{full_path}"
        return false
      end

      # Unmount
      error_io = IO::Memory.new
      result = Process.run("umount", [full_path],
                         output: Process::Redirect::Pipe,
                         error: error_io)

      unless result.success?
        puts "Error: Failed to unmount: #{error_io.to_s}"
        return false
      end

      # Remove from config
      @storage.config.mounts.reject! { |m| m.path == full_path }
      @storage.persist_config

      # Remove mount point directory
      Dir.delete(full_path) if Dir.exists?(full_path)

      true
    end
  end
end
