require "./cli"
require "./config"
require "./storage"

module JJFS
  VERSION = "0.1.0"
end

JJFS::CLI.run(ARGV)
