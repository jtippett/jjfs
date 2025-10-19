require "../mount_manager"
require "../storage"

module JJFS::Commands
  class Open
    def initialize(@storage : Storage, @repo_name : String, @path : String?)
    end

    def execute
      # Default path: ./<repo_name>
      mount_path = @path || File.join(Dir.current, @repo_name)

      manager = MountManager.new(@storage)

      if mount = manager.mount(@repo_name, mount_path)
        puts "Opened #{@repo_name} at #{mount.path}"
        true
      else
        false
      end
    end
  end
end
