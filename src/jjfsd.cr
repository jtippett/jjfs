# Daemon entry point for jjfsd
module JJFS
  class Daemon
    def run
      puts "jjfsd starting..."
    end
  end
end

daemon = JJFS::Daemon.new
daemon.run
