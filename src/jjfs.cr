require "./cli"
require "./config"
require "./storage"

module JJFS
  VERSION = "0.1.2"
end

JJFS::CLI.run(ARGV)
