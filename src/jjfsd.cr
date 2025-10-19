require "./daemon"
require "./storage"

storage = JJFS::Storage.new
daemon = JJFS::Daemon.new(storage)

Signal::INT.trap do
  daemon.stop
  exit
end

daemon.start
