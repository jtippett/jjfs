# CLI entry point for jjfs
require "option_parser"

module JJFS
  VERSION = "0.1.0"

  def self.run
    puts "jjfs v#{VERSION}"
  end
end

JJFS.run
