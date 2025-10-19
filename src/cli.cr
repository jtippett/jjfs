require "option_parser"
require "./commands/init"
require "./storage"

module JJFS
  class CLI
    getter command : Symbol
    getter args : Array(String)
    getter options : Hash(String, String)

    def initialize(argv : Array(String))
      @command = :help
      @args = [] of String
      @options = {} of String => String

      parse(argv)
    end

    private def parse(argv)
      return if argv.empty?

      cmd = argv[0]
      # Convert string to symbol manually in Crystal
      case cmd
      when "init"
        @command = :init
      when "open"
        @command = :open
      when "close"
        @command = :close
      when "list"
        @command = :list
      when "status"
        @command = :status
      when "start"
        @command = :start
      when "stop"
        @command = :stop
      when "sync"
        @command = :sync
      when "remote"
        @command = :remote
      when "install"
        @command = :install
      else
        @command = :help
      end

      @args = argv[1..]

      # Options parsing can be added per-command later
    end

    def self.run(argv : Array(String))
      cli = new(argv)

      case cli.command
      when :init
        storage = Storage.new
        storage.ensure_directories
        repo_name = cli.args.first? || "default"
        cmd = Commands::Init.new(storage, repo_name)
        exit(cmd.execute ? 0 : 1)
      when :open
        puts "TODO: open #{cli.args}"
      when :close
        puts "TODO: close #{cli.args}"
      when :list
        puts "TODO: list mounts"
      when :status
        puts "TODO: daemon status"
      when :start
        puts "TODO: start daemon"
      when :stop
        puts "TODO: stop daemon"
      when :sync
        puts "TODO: sync #{cli.args.first? || "all"}"
      when :remote
        puts "TODO: remote #{cli.args}"
      when :install
        puts "TODO: install service"
      else
        show_help
      end
    end

    def self.show_help
      puts <<-HELP
      jjfs v#{VERSION} - Eventually Consistent Multi-Mount Filesystem

      USAGE:
        jjfs <command> [args]

      COMMANDS:
        init [name]              Initialize a repo (default: "default")
        open <repo> [path]       Open repo at path (default: ./<repo>)
        close <path>             Close mount at path
        list                     List all mounts
        status                   Show daemon status
        start                    Start daemon
        stop                     Stop daemon
        sync [repo]              Force sync (default: all repos)
        remote add <url> [--repo=name]
        install                  Install system service
      HELP
    end
  end
end
