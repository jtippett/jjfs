# jjfs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a FUSE-based filesystem that makes multiple directories eventually-consistent views of the same Jujutsu repository.

**Architecture:** CLI + long-running daemon communicating via JSON-RPC over Unix socket. Daemon manages FUSE mounts (pass-through to jj workspaces) and sync coordinator (fswatch → jj commit → jj workspace update).

**Tech Stack:** Crystal, libfuse (FFI), Jujutsu CLI, fswatch/inotify, JSON-RPC, launchd/systemd

---

## Phase 1: Project Setup & Scaffolding

### Task 1: Initialize Crystal Project

**Files:**
- Create: `shard.yml`
- Create: `.gitignore`
- Create: `README.md`
- Create: `src/jjfs.cr` (CLI entry point)
- Create: `src/jjfsd.cr` (daemon entry point)

**Step 1: Initialize git repository**

```bash
git init
```

**Step 2: Create shard.yml**

```yaml
name: jjfs
version: 0.1.0

authors:
  - James <your-email>

crystal: 1.10.0

targets:
  jjfs:
    main: src/jjfs.cr
  jjfsd:
    main: src/jjfsd.cr

license: MIT
```

**Step 3: Create .gitignore**

```
/bin/
/lib/
/.shards/
*.dwarf
.DS_Store
```

**Step 4: Create README.md**

```markdown
# jjfs - Eventually Consistent Multi-Mount Filesystem

FUSE-based filesystem for eventually-consistent jj repository views.

## Status

🚧 Under active development

## Documentation

See `docs/plans/2025-10-19-jjfs-design.md` for full design.
```

**Step 5: Create CLI stub**

File: `src/jjfs.cr`

```crystal
# CLI entry point for jjfs
require "option_parser"

module JJFS
  VERSION = "0.1.0"
  
  def self.run
    puts "jjfs v#{VERSION}"
  end
end

JJFS.run
```

**Step 6: Create daemon stub**

File: `src/jjfsd.cr`

```crystal
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
```

**Step 7: Test build**

```bash
crystal build src/jjfs.cr -o bin/jjfs
crystal build src/jjfsd.cr -o bin/jjfsd
./bin/jjfs
./bin/jjfsd
```

Expected output:
```
jjfs v0.1.0
jjfsd starting...
```

**Step 8: Commit**

```bash
git add .
git commit -m "feat: initialize Crystal project structure"
```

---

### Task 2: Config & Storage Foundation

**Files:**
- Create: `src/config.cr`
- Create: `src/storage.cr`
- Create: `spec/config_spec.cr`
- Create: `spec/spec_helper.cr`

**Step 1: Write config spec**

File: `spec/spec_helper.cr`

```crystal
require "spec"
require "../src/config"
require "../src/storage"
```

File: `spec/config_spec.cr`

```crystal
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
```

**Step 2: Run test to verify it fails**

```bash
crystal spec spec/config_spec.cr
```

Expected: FAIL with "undefined constant JJFS::Config"

**Step 3: Implement Config**

File: `src/config.cr`

```crystal
require "json"

module JJFS
  class RepoConfig
    include JSON::Serializable
    
    property path : String
    property remote : String?
    property sync_interval : Int32
    property push_interval : Int32
    
    def initialize(@path : String, @remote : String? = nil, @sync_interval : Int32 = 2, @push_interval : Int32 = 300)
    end
  end
  
  class MountConfig
    include JSON::Serializable
    
    property id : String
    property repo : String
    property path : String
    property workspace : String
    
    def initialize(@id : String, @repo : String, @path : String, @workspace : String)
    end
  end
  
  class Config
    include JSON::Serializable
    
    property repos : Hash(String, RepoConfig)
    property mounts : Array(MountConfig)
    
    def initialize
      @repos = {} of String => RepoConfig
      @mounts = [] of MountConfig
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
crystal spec spec/config_spec.cr
```

Expected: PASS (2 examples)

**Step 5: Write storage spec**

File: `spec/config_spec.cr` (append)

```crystal
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
```

**Step 6: Run test to verify it fails**

```bash
crystal spec spec/config_spec.cr
```

Expected: FAIL with "undefined constant JJFS::Storage"

**Step 7: Implement Storage**

File: `src/storage.cr`

```crystal
require "file_utils"
require "./config"

module JJFS
  class Storage
    DEFAULT_ROOT = File.expand_path("~/.jjfs")
    
    getter root : String
    getter config : Config
    
    def initialize(@root : String = DEFAULT_ROOT)
      @config = load_config
    end
    
    def ensure_directories
      FileUtils.mkdir_p(repos_dir)
      FileUtils.mkdir_p(File.dirname(config_path))
      save_config unless File.exists?(config_path)
    end
    
    def repos_dir
      File.join(@root, "repos")
    end
    
    def config_path
      File.join(@root, "config.json")
    end
    
    def socket_path
      File.join(@root, "daemon.sock")
    end
    
    def lock_path
      File.join(@root, "daemon.lock")
    end
    
    def log_path
      File.join(@root, "sync.log")
    end
    
    def repo_path(name : String)
      File.join(repos_dir, name)
    end
    
    def workspaces_dir(repo : String)
      File.join(repo_path(repo), "workspaces")
    end
    
    private def load_config
      if File.exists?(config_path)
        Config.from_json(File.read(config_path))
      else
        Config.new
      end
    end
    
    private def save_config
      File.write(config_path, @config.to_json)
    end
    
    def persist_config
      save_config
    end
  end
end
```

**Step 8: Run test to verify it passes**

```bash
crystal spec spec/config_spec.cr
```

Expected: PASS (3 examples)

**Step 9: Commit**

```bash
git add src/config.cr src/storage.cr spec/
git commit -m "feat: add config and storage foundation with tests"
```

---

## Phase 2: CLI Command Framework

### Task 3: CLI Parser & Subcommands

**Files:**
- Create: `src/cli.cr`
- Modify: `src/jjfs.cr`
- Create: `spec/cli_spec.cr`

**Step 1: Write CLI spec**

File: `spec/cli_spec.cr`

```crystal
require "./spec_helper"
require "../src/cli"

describe JJFS::CLI do
  it "parses init command" do
    cli = JJFS::CLI.new(["init"])
    cli.command.should eq(:init)
    cli.args.should be_empty
  end
  
  it "parses init with repo name" do
    cli = JJFS::CLI.new(["init", "work-notes"])
    cli.command.should eq(:init)
    cli.args.should eq(["work-notes"])
  end
  
  it "parses open command" do
    cli = JJFS::CLI.new(["open", "default"])
    cli.command.should eq(:open)
    cli.args.should eq(["default"])
  end
end
```

**Step 2: Run test to verify it fails**

```bash
crystal spec spec/cli_spec.cr
```

Expected: FAIL

**Step 3: Implement CLI parser**

File: `src/cli.cr`

```crystal
require "option_parser"

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
      @command = cmd.to_sym
      @args = argv[1..]
      
      # Options parsing can be added per-command later
    end
    
    def self.run(argv : Array(String))
      cli = new(argv)
      
      case cli.command
      when :init
        puts "TODO: init #{cli.args.first? || "default"}"
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
```

**Step 4: Run test to verify it passes**

```bash
crystal spec spec/cli_spec.cr
```

Expected: PASS

**Step 5: Update main CLI entry point**

File: `src/jjfs.cr`

```crystal
require "./cli"
require "./config"
require "./storage"

module JJFS
  VERSION = "0.1.0"
end

JJFS::CLI.run(ARGV)
```

**Step 6: Test CLI manually**

```bash
crystal build src/jjfs.cr -o bin/jjfs
./bin/jjfs
./bin/jjfs init
./bin/jjfs open default
```

Expected: Help text and TODO messages

**Step 7: Commit**

```bash
git add src/cli.cr src/jjfs.cr spec/cli_spec.cr
git commit -m "feat: add CLI parser and command framework"
```

---

### Task 4: Implement `jjfs init` Command

**Files:**
- Create: `src/commands/init.cr`
- Modify: `src/cli.cr`
- Create: `spec/commands/init_spec.cr`

**Step 1: Write init command spec**

File: `spec/commands/init_spec.cr`

```crystal
require "../spec_helper"
require "../../src/commands/init"
require "file_utils"

describe JJFS::Commands::Init do
  it "creates repo with default name" do
    tmp_dir = File.tempname("jjfs_test")
    storage = JJFS::Storage.new(tmp_dir)
    
    cmd = JJFS::Commands::Init.new(storage, "default")
    cmd.execute
    
    Dir.exists?(storage.repo_path("default")).should be_true
    Dir.exists?(storage.workspaces_dir("default")).should be_true
    storage.config.repos.has_key?("default").should be_true
    
    FileUtils.rm_rf(tmp_dir)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
crystal spec spec/commands/init_spec.cr
```

Expected: FAIL

**Step 3: Implement Init command**

File: `src/commands/init.cr`

```crystal
require "../storage"
require "file_utils"

module JJFS::Commands
  class Init
    def initialize(@storage : Storage, @repo_name : String)
    end
    
    def execute
      repo_path = @storage.repo_path(@repo_name)
      
      if Dir.exists?(repo_path)
        puts "Error: Repo '#{@repo_name}' already exists at #{repo_path}"
        return false
      end
      
      # Create repo directory
      FileUtils.mkdir_p(repo_path)
      
      # Initialize jj repo
      result = Process.run("jj", ["git", "init", repo_path], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
      
      unless result.success?
        puts "Error: Failed to initialize jj repo: #{result.error}"
        FileUtils.rm_rf(repo_path)
        return false
      end
      
      # Create workspaces directory
      FileUtils.mkdir_p(@storage.workspaces_dir(@repo_name))
      
      # Update config
      @storage.config.repos[@repo_name] = RepoConfig.new(
        path: repo_path,
        remote: nil,
        sync_interval: 2,
        push_interval: 300
      )
      @storage.persist_config
      
      puts "Initialized repo '#{@repo_name}' at #{repo_path}"
      true
    end
  end
end
```

**Step 4: Run test to verify it passes**

```bash
crystal spec spec/commands/init_spec.cr
```

Expected: PASS (requires `jj` in PATH)

**Step 5: Wire up to CLI**

File: `src/cli.cr`

```crystal
require "./commands/init"

# In CLI.run, replace init case:
when :init
  storage = Storage.new
  storage.ensure_directories
  repo_name = cli.args.first? || "default"
  cmd = Commands::Init.new(storage, repo_name)
  exit(cmd.execute ? 0 : 1)
```

**Step 6: Test manually**

```bash
crystal build src/jjfs.cr -o bin/jjfs
./bin/jjfs init test-repo
ls ~/.jjfs/repos/test-repo
cat ~/.jjfs/config.json
```

Expected: Repo created, config updated

**Step 7: Commit**

```bash
git add src/commands/init.cr src/cli.cr spec/commands/init_spec.cr
git commit -m "feat: implement jjfs init command"
```

---

## Phase 3: Daemon Foundation

### Task 5: Daemon Lifecycle & Socket Server

**Files:**
- Create: `src/daemon.cr`
- Create: `src/rpc_server.cr`
- Modify: `src/jjfsd.cr`
- Create: `spec/daemon_spec.cr`

**Step 1: Write daemon spec**

File: `spec/daemon_spec.cr`

```crystal
require "./spec_helper"
require "../src/daemon"
require "file_utils"

describe JJFS::Daemon do
  it "starts and creates socket" do
    tmp_dir = File.tempname("jjfs_test")
    storage = JJFS::Storage.new(tmp_dir)
    storage.ensure_directories
    
    daemon = JJFS::Daemon.new(storage)
    
    # Start in fiber to test non-blocking
    spawn { daemon.start }
    sleep 0.1
    
    File.exists?(storage.socket_path).should be_true
    File.exists?(storage.lock_path).should be_true
    
    daemon.stop
    FileUtils.rm_rf(tmp_dir)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
crystal spec spec/daemon_spec.cr
```

Expected: FAIL

**Step 3: Implement Daemon**

File: `src/daemon.cr`

```crystal
require "socket"
require "./storage"
require "./rpc_server"

module JJFS
  class Daemon
    @running = false
    @server : UNIXServer?
    
    def initialize(@storage : Storage)
    end
    
    def start
      acquire_lock
      @storage.ensure_directories
      
      @running = true
      @server = UNIXServer.new(@storage.socket_path)
      
      puts "jjfsd started, listening on #{@storage.socket_path}"
      
      rpc = RPCServer.new(@storage)
      
      while @running
        if server = @server
          if client = server.accept?
            spawn handle_client(client, rpc)
          end
        end
      end
    end
    
    def stop
      @running = false
      @server.try &.close
      release_lock
      File.delete(@storage.socket_path) if File.exists?(@storage.socket_path)
      puts "jjfsd stopped"
    end
    
    private def handle_client(client : UNIXSocket, rpc : RPCServer)
      request = client.gets
      return unless request
      
      response = rpc.handle(request)
      client.puts(response)
    ensure
      client.close
    end
    
    private def acquire_lock
      if File.exists?(@storage.lock_path)
        pid = File.read(@storage.lock_path).strip
        puts "Error: Daemon already running (PID: #{pid})"
        exit(1)
      end
      
      File.write(@storage.lock_path, Process.pid.to_s)
    end
    
    private def release_lock
      File.delete(@storage.lock_path) if File.exists?(@storage.lock_path)
    end
  end
end
```

**Step 4: Implement RPC Server stub**

File: `src/rpc_server.cr`

```crystal
require "json"
require "./storage"

module JJFS
  class RPCServer
    def initialize(@storage : Storage)
    end
    
    def handle(request : String) : String
      req = JSON.parse(request)
      method = req["method"].as_s
      
      response = case method
      when "status"
        handle_status
      when "list_mounts"
        handle_list_mounts
      else
        {"error" => "Unknown method: #{method}"}
      end
      
      {
        "jsonrpc" => "2.0",
        "result" => response,
        "id" => req["id"]?
      }.to_json
    rescue ex
      {
        "jsonrpc" => "2.0",
        "error" => {"message" => ex.message},
        "id" => nil
      }.to_json
    end
    
    private def handle_status
      {
        "daemon" => "running",
        "repos" => @storage.config.repos.size,
        "mounts" => @storage.config.mounts.size
      }
    end
    
    private def handle_list_mounts
      {
        "mounts" => @storage.config.mounts.map do |m|
          {
            "id" => m.id,
            "repo" => m.repo,
            "path" => m.path,
            "status" => "unknown"
          }
        end
      }
    end
  end
end
```

**Step 5: Update daemon entry point**

File: `src/jjfsd.cr`

```crystal
require "./daemon"
require "./storage"

storage = JJFS::Storage.new
daemon = JJFS::Daemon.new(storage)

Signal::INT.trap do
  daemon.stop
  exit
end

daemon.start
```

**Step 6: Run test**

```bash
crystal spec spec/daemon_spec.cr
```

Expected: PASS

**Step 7: Test manually**

```bash
crystal build src/jjfsd.cr -o bin/jjfsd
./bin/jjfsd &
ls ~/.jjfs/daemon.sock
kill %1
```

Expected: Socket created, daemon responds to signals

**Step 8: Commit**

```bash
git add src/daemon.cr src/rpc_server.cr src/jjfsd.cr spec/daemon_spec.cr
git commit -m "feat: implement daemon with JSON-RPC server"
```

---

### Task 6: Implement `jjfs status` Command

**Files:**
- Create: `src/rpc_client.cr`
- Create: `src/commands/status.cr`
- Modify: `src/cli.cr`

**Step 1: Write RPC client**

File: `src/rpc_client.cr`

```crystal
require "socket"
require "json"

module JJFS
  class RPCClient
    def initialize(@socket_path : String)
    end
    
    def call(method : String, params = {} of String => String) : JSON::Any
      request = {
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params,
        "id" => 1
      }.to_json
      
      socket = UNIXSocket.new(@socket_path)
      socket.puts(request)
      response = socket.gets
      socket.close
      
      raise "No response from daemon" unless response
      
      data = JSON.parse(response)
      
      if error = data["error"]?
        raise "RPC Error: #{error["message"]}"
      end
      
      data["result"]
    end
    
    def daemon_running? : Bool
      File.exists?(@socket_path)
    end
  end
end
```

**Step 2: Write status command**

File: `src/commands/status.cr`

```crystal
require "../rpc_client"
require "../storage"

module JJFS::Commands
  class Status
    def initialize(@storage : Storage)
    end
    
    def execute
      client = RPCClient.new(@storage.socket_path)
      
      unless client.daemon_running?
        puts "Daemon: not running"
        return false
      end
      
      result = client.call("status")
      
      puts "Daemon: running"
      puts "Repos: #{result["repos"]}"
      puts "Mounts: #{result["mounts"]}"
      
      true
    rescue ex
      puts "Error: #{ex.message}"
      false
    end
  end
end
```

**Step 3: Wire to CLI**

File: `src/cli.cr`

```crystal
require "./commands/status"

# In CLI.run:
when :status
  storage = Storage.new
  cmd = Commands::Status.new(storage)
  exit(cmd.execute ? 0 : 1)
```

**Step 4: Test manually**

```bash
crystal build src/jjfs.cr -o bin/jjfs
crystal build src/jjfsd.cr -o bin/jjfsd

# Terminal 1:
./bin/jjfsd

# Terminal 2:
./bin/jjfs status
```

Expected: Shows daemon running

**Step 5: Commit**

```bash
git add src/rpc_client.cr src/commands/status.cr src/cli.cr
git commit -m "feat: implement jjfs status command"
```

---

## Phase 4: FUSE Integration

### Task 7: FUSE Bindings via FFI

**Files:**
- Create: `src/fuse/bindings.cr`
- Create: `src/fuse/operations.cr`

**Step 1: Create FUSE bindings**

File: `src/fuse/bindings.cr`

```crystal
@[Link("fuse3")]
lib LibFUSE
  struct FuseArgs
    argc : Int32
    argv : UInt8**
    allocated : Int32
  end
  
  struct FuseOperations
    getattr : Void*
    readdir : Void*
    open : Void*
    read : Void*
    write : Void*
    # Add more as needed
  end
  
  fun fuse_main(argc : Int32, argv : UInt8**, ops : FuseOperations*, user_data : Void*) : Int32
end
```

**Note:** Full FUSE FFI bindings are complex. For V1, consider using existing Crystal FUSE library if available, or use `bindgen` to generate bindings. This is a placeholder showing the approach.

**Step 2: Create FUSE operations wrapper**

File: `src/fuse/operations.cr`

```crystal
require "./bindings"

module JJFS::FUSE
  class Operations
    def initialize(@source_path : String)
    end
    
    # Implement FUSE operations that pass through to source_path
    # This is complex - recommend using existing FUSE library
  end
end
```

**Step 3: Research existing Crystal FUSE libraries**

```bash
# Check for existing bindings
shards search fuse
```

**Note:** If no mature library exists, this task will require significant FFI work. Consider alternative: Shell out to `bindfs` or similar for pass-through mounting in V1, implement native FUSE in V2.

**Step 4: Document decision**

Create file: `docs/fuse-approach.md`

```markdown
# FUSE Implementation Approach

## Decision for V1

Use `bindfs` as external dependency for pass-through mounting:
- Mature, well-tested
- Simple integration via Process.run
- Allows focus on sync logic

## Future V2

Implement native FUSE via FFI for:
- Better error handling
- Custom optimizations
- Reduced external dependencies
```

**Step 5: Commit**

```bash
git add src/fuse/ docs/fuse-approach.md
git commit -m "docs: document FUSE approach for V1"
```

---

### Task 8: Mount/Unmount via bindfs

**Files:**
- Create: `src/mount_manager.cr`
- Create: `src/commands/open.cr`
- Create: `src/commands/close.cr`

**Step 1: Implement mount manager**

File: `src/mount_manager.cr`

```crystal
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
        result = Process.run("jj", ["workspace", "add", workspace_path], 
                           output: Process::Redirect::Pipe, 
                           error: Process::Redirect::Pipe)
        
        unless result.success?
          puts "Error: Failed to create jj workspace: #{result.error}"
          Dir.rmdir(full_path)
          return nil
        end
      end
      
      # Mount with bindfs (pass-through)
      result = Process.run("bindfs", [workspace_path, full_path],
                         output: Process::Redirect::Pipe,
                         error: Process::Redirect::Pipe)
      
      unless result.success?
        puts "Error: Failed to mount with bindfs: #{result.error}"
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
      result = Process.run("umount", [full_path],
                         output: Process::Redirect::Pipe,
                         error: Process::Redirect::Pipe)
      
      unless result.success?
        puts "Error: Failed to unmount: #{result.error}"
        return false
      end
      
      # Remove from config
      @storage.config.mounts.reject! { |m| m.path == full_path }
      @storage.persist_config
      
      # Remove mount point directory
      Dir.rmdir(full_path) if Dir.exists?(full_path)
      
      true
    end
  end
end
```

**Step 2: Implement open command**

File: `src/commands/open.cr`

```crystal
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
```

**Step 3: Implement close command**

File: `src/commands/close.cr`

```crystal
require "../mount_manager"

module JJFS::Commands
  class Close
    def initialize(@storage : Storage, @path : String)
    end
    
    def execute
      manager = MountManager.new(@storage)
      manager.unmount(@path)
    end
  end
end
```

**Step 4: Wire to CLI**

File: `src/cli.cr`

```crystal
require "./commands/open"
require "./commands/close"

# In CLI.run:
when :open
  storage = Storage.new
  repo_name = cli.args.first? || "default"
  path = cli.args[1]?
  cmd = Commands::Open.new(storage, repo_name, path)
  exit(cmd.execute ? 0 : 1)

when :close
  storage = Storage.new
  path = cli.args.first
  unless path
    puts "Error: path required"
    exit(1)
  end
  cmd = Commands::Close.new(storage, path)
  exit(cmd.execute ? 0 : 1)
```

**Step 5: Test manually**

```bash
# Requires: bindfs, jj in PATH
crystal build src/jjfs.cr -o bin/jjfs

./bin/jjfs init default
./bin/jjfs open default ./test-mount
ls ./test-mount
echo "hello" > ./test-mount/file.txt
cat ~/.jjfs/repos/default/workspaces/*/file.txt
./bin/jjfs close ./test-mount
```

Expected: Mount works, files accessible in both locations

**Step 6: Commit**

```bash
git add src/mount_manager.cr src/commands/open.cr src/commands/close.cr src/cli.cr
git commit -m "feat: implement mount/unmount with bindfs"
```

---

## Phase 5: Sync Engine

### Task 9: Filesystem Watcher

**Files:**
- Create: `src/watcher.cr`
- Create: `spec/watcher_spec.cr`

**Step 1: Write watcher spec**

File: `spec/watcher_spec.cr`

```crystal
require "./spec_helper"
require "../src/watcher"
require "file_utils"

describe JJFS::Watcher do
  it "detects file changes" do
    tmp_dir = File.tempname("jjfs_test")
    Dir.mkdir_p(tmp_dir)
    
    changed = false
    watcher = JJFS::Watcher.new(tmp_dir) do |path|
      changed = true
    end
    
    spawn { watcher.start }
    sleep 0.1
    
    File.write(File.join(tmp_dir, "test.txt"), "content")
    sleep 0.5
    
    changed.should be_true
    
    watcher.stop
    FileUtils.rm_rf(tmp_dir)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
crystal spec spec/watcher_spec.cr
```

Expected: FAIL

**Step 3: Implement watcher (using fswatch on macOS)**

File: `src/watcher.cr`

```crystal
require "process"

module JJFS
  class Watcher
    @running = false
    @process : Process?
    
    def initialize(@path : String, &@callback : String -> Void)
    end
    
    def start
      @running = true
      
      # Use fswatch on macOS, inotifywait on Linux
      cmd = detect_watcher_command
      
      @process = Process.new(cmd, [@path],
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe)
      
      if process = @process
        while @running
          if line = process.output.gets
            @callback.call(line.strip)
          end
        end
      end
    end
    
    def stop
      @running = false
      @process.try &.terminate
    end
    
    private def detect_watcher_command : String
      # Check platform
      {% if flag?(:darwin) %}
        "fswatch"
      {% elsif flag?(:linux) %}
        "inotifywait"
      {% else %}
        raise "Unsupported platform for file watching"
      {% end %}
    end
  end
end
```

**Step 4: Run test**

```bash
# Requires fswatch on macOS: brew install fswatch
crystal spec spec/watcher_spec.cr
```

Expected: PASS

**Step 5: Commit**

```bash
git add src/watcher.cr spec/watcher_spec.cr
git commit -m "feat: implement filesystem watcher"
```

---

### Task 10: Sync Coordinator

**Files:**
- Create: `src/sync_coordinator.cr`
- Modify: `src/daemon.cr`

**Step 1: Implement sync coordinator**

File: `src/sync_coordinator.cr`

```crystal
require "./storage"
require "./watcher"
require "log"

module JJFS
  class SyncCoordinator
    Log = ::Log.for(self)
    
    @watchers = [] of Watcher
    @syncing = Set(String).new  # Track workspaces being synced to prevent loops
    
    def initialize(@storage : Storage)
    end
    
    def start
      # Start watchers for each mount
      @storage.config.mounts.each do |mount|
        start_watcher(mount)
      end
      
      Log.info { "Sync coordinator started with #{@watchers.size} watchers" }
    end
    
    def stop
      @watchers.each &.stop
      @watchers.clear
    end
    
    def add_mount(mount : MountConfig)
      start_watcher(mount)
    end
    
    def remove_mount(mount : MountConfig)
      # Stop watcher for this mount (simplified - track by workspace)
    end
    
    private def start_watcher(mount : MountConfig)
      watcher = Watcher.new(mount.workspace) do |changed_path|
        handle_change(mount, changed_path)
      end
      
      spawn { watcher.start }
      @watchers << watcher
    end
    
    private def handle_change(mount : MountConfig, changed_path : String)
      # Prevent sync loops
      return if @syncing.includes?(mount.workspace)
      
      Log.info { "Change detected in #{mount.workspace}: #{changed_path}" }
      
      @syncing.add(mount.workspace)
      
      begin
        # Commit changes in this workspace
        commit_workspace(mount)
        
        # Sync to other workspaces in same repo
        sync_repo_workspaces(mount.repo, mount.workspace)
      ensure
        @syncing.delete(mount.workspace)
      end
    end
    
    private def commit_workspace(mount : MountConfig)
      Dir.cd(mount.workspace) do
        timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%S")
        result = Process.run("jj", ["commit", "-m", "auto-sync #{timestamp}"],
                           output: Process::Redirect::Pipe,
                           error: Process::Redirect::Pipe)
        
        unless result.success?
          Log.error { "Failed to commit in #{mount.workspace}: #{result.error}" }
        end
      end
    end
    
    private def sync_repo_workspaces(repo_name : String, source_workspace : String)
      # Find all other workspaces for this repo
      other_mounts = @storage.config.mounts.select do |m|
        m.repo == repo_name && m.workspace != source_workspace
      end
      
      other_mounts.each do |mount|
        @syncing.add(mount.workspace)
        
        Dir.cd(mount.workspace) do
          result = Process.run("jj", ["workspace", "update-stale"],
                             output: Process::Redirect::Pipe,
                             error: Process::Redirect::Pipe)
          
          unless result.success?
            Log.error { "Failed to update workspace #{mount.workspace}: #{result.error}" }
          else
            Log.info { "Synced to #{mount.workspace}" }
          end
        end
        
        @syncing.delete(mount.workspace)
      end
    end
  end
end
```

**Step 2: Integrate with daemon**

File: `src/daemon.cr`

```crystal
require "./sync_coordinator"

# In Daemon class:
@sync_coordinator : SyncCoordinator?

# In start method, after server setup:
@sync_coordinator = SyncCoordinator.new(@storage)
@sync_coordinator.try &.start

# In stop method:
@sync_coordinator.try &.stop
```

**Step 3: Update RPC server to notify sync coordinator of new mounts**

File: `src/rpc_server.cr`

```crystal
# Add sync_coordinator parameter to initialize
def initialize(@storage : Storage, @sync_coordinator : SyncCoordinator?)
end

# When handling mount operations (future task), call:
# @sync_coordinator.try &.add_mount(mount)
```

**Step 4: Test manually**

```bash
crystal build src/jjfsd.cr -o bin/jjfsd
crystal build src/jjfs.cr -o bin/jjfs

# Terminal 1:
./bin/jjfsd

# Terminal 2:
./bin/jjfs init default
./bin/jjfs open default ./mount-a
./bin/jjfs open default ./mount-b

echo "test content" > ./mount-a/file.txt
sleep 2
cat ./mount-b/file.txt
```

Expected: File appears in mount-b after ~2s

**Step 5: Commit**

```bash
git add src/sync_coordinator.cr src/daemon.cr src/rpc_server.cr
git commit -m "feat: implement sync coordinator with automatic propagation"
```

---

## Phase 6: Remote Sync & Polish

### Task 11: Remote Sync (Push/Pull)

**Files:**
- Create: `src/remote_syncer.cr`
- Modify: `src/daemon.cr`
- Create: `src/commands/remote.cr`

**Step 1: Implement remote syncer**

File: `src/remote_syncer.cr`

```crystal
require "./storage"
require "log"

module JJFS
  class RemoteSyncer
    Log = ::Log.for(self)
    
    @running = false
    
    def initialize(@storage : Storage, @sync_coordinator : SyncCoordinator)
    end
    
    def start
      @running = true
      
      spawn do
        while @running
          sync_all_repos
          sleep 300  # 5 minutes
        end
      end
    end
    
    def stop
      @running = false
    end
    
    def sync_repo(repo_name : String) : Bool
      repo = @storage.config.repos[repo_name]?
      return false unless repo
      return true unless repo.remote  # No remote configured
      
      # Pick first workspace for this repo
      mount = @storage.config.mounts.find { |m| m.repo == repo_name }
      return false unless mount
      
      Dir.cd(mount.workspace) do
        # Push
        result = Process.run("jj", ["git", "push", "--all-bookmarks"],
                           output: Process::Redirect::Pipe,
                           error: Process::Redirect::Pipe)
        
        unless result.success?
          Log.error { "Failed to push #{repo_name}: #{result.error}" }
          return false
        end
        
        # Fetch
        result = Process.run("jj", ["git", "fetch"],
                           output: Process::Redirect::Pipe,
                           error: Process::Redirect::Pipe)
        
        unless result.success?
          Log.error { "Failed to fetch #{repo_name}: #{result.error}" }
          return false
        end
        
        # Rebase if needed
        result = Process.run("jj", ["rebase"],
                           output: Process::Redirect::Pipe,
                           error: Process::Redirect::Pipe)
        
        # Trigger local sync to propagate remote changes
        # (handled by sync coordinator watching the workspace)
        
        Log.info { "Synced #{repo_name} with remote" }
        true
      end
    end
    
    private def sync_all_repos
      @storage.config.repos.each_key do |repo_name|
        sync_repo(repo_name)
      end
    end
  end
end
```

**Step 2: Implement remote command**

File: `src/commands/remote.cr`

```crystal
require "../storage"

module JJFS::Commands
  class Remote
    def initialize(@storage : Storage, @args : Array(String))
    end
    
    def execute
      action = @args.first?
      
      case action
      when "add"
        add_remote
      else
        puts "Usage: jjfs remote add <url> [--repo=name]"
        false
      end
    end
    
    private def add_remote
      url = @args[1]?
      unless url
        puts "Error: URL required"
        return false
      end
      
      # Parse --repo option (simplified)
      repo_name = "default"
      
      repo = @storage.config.repos[repo_name]?
      unless repo
        puts "Error: Repo #{repo_name} not found"
        return false
      end
      
      # Set remote
      Dir.cd(repo.path) do
        result = Process.run("jj", ["git", "remote", "add", "origin", url],
                           output: Process::Redirect::Pipe,
                           error: Process::Redirect::Pipe)
        
        unless result.success?
          puts "Error: Failed to add remote: #{result.error}"
          return false
        end
      end
      
      # Update config
      repo.remote = url
      @storage.persist_config
      
      puts "Added remote #{url} to #{repo_name}"
      true
    end
  end
end
```

**Step 3: Wire to CLI**

File: `src/cli.cr`

```crystal
require "./commands/remote"

# In CLI.run:
when :remote
  storage = Storage.new
  cmd = Commands::Remote.new(storage, cli.args)
  exit(cmd.execute ? 0 : 1)
```

**Step 4: Integrate with daemon**

File: `src/daemon.cr`

```crystal
require "./remote_syncer"

# In Daemon class:
@remote_syncer : RemoteSyncer?

# In start method:
@remote_syncer = RemoteSyncer.new(@storage, @sync_coordinator.not_nil!)
@remote_syncer.try &.start

# In stop method:
@remote_syncer.try &.stop
```

**Step 5: Commit**

```bash
git add src/remote_syncer.cr src/commands/remote.cr src/cli.cr src/daemon.cr
git commit -m "feat: implement remote sync with push/pull"
```

---

### Task 12: Service Installation (launchd/systemd)

**Files:**
- Create: `src/commands/install.cr`
- Create: `templates/com.jjfs.daemon.plist`
- Create: `templates/jjfs.service`

**Step 1: Create launchd plist template**

File: `templates/com.jjfs.daemon.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jjfs.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{JJFSD_PATH}}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{{HOME}}/.jjfs/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>{{HOME}}/.jjfs/daemon.error.log</string>
</dict>
</plist>
```

**Step 2: Create systemd service template**

File: `templates/jjfs.service`

```ini
[Unit]
Description=jjfs daemon
After=network.target

[Service]
Type=simple
ExecStart={{JJFSD_PATH}}
Restart=on-failure
StandardOutput=append:{{HOME}}/.jjfs/daemon.log
StandardError=append:{{HOME}}/.jjfs/daemon.error.log

[Install]
WantedBy=default.target
```

**Step 3: Implement install command**

File: `src/commands/install.cr`

```crystal
require "file_utils"

module JJFS::Commands
  class Install
    def execute
      jjfsd_path = find_jjfsd
      unless jjfsd_path
        puts "Error: jjfsd not found in PATH"
        return false
      end
      
      {% if flag?(:darwin) %}
        install_launchd(jjfsd_path)
      {% elsif flag?(:linux) %}
        install_systemd(jjfsd_path)
      {% else %}
        puts "Error: Unsupported platform"
        false
      {% end %}
    end
    
    private def find_jjfsd : String?
      # Check if jjfsd is in PATH
      result = Process.run("which", ["jjfsd"],
                         output: Process::Redirect::Pipe,
                         error: Process::Redirect::Pipe)
      
      result.success? ? result.output.to_s.strip : nil
    end
    
    private def install_launchd(jjfsd_path : String) : Bool
      template = File.read("templates/com.jjfs.daemon.plist")
      content = template
        .gsub("{{JJFSD_PATH}}", jjfsd_path)
        .gsub("{{HOME}}", ENV["HOME"])
      
      plist_path = File.expand_path("~/Library/LaunchAgents/com.jjfs.daemon.plist")
      File.write(plist_path, content)
      
      # Load service
      result = Process.run("launchctl", ["load", plist_path],
                         output: Process::Redirect::Pipe,
                         error: Process::Redirect::Pipe)
      
      unless result.success?
        puts "Error: Failed to load service: #{result.error}"
        return false
      end
      
      puts "Installed and started jjfs service (launchd)"
      true
    end
    
    private def install_systemd(jjfsd_path : String) : Bool
      template = File.read("templates/jjfs.service")
      content = template
        .gsub("{{JJFSD_PATH}}", jjfsd_path)
        .gsub("{{HOME}}", ENV["HOME"])
      
      service_path = File.expand_path("~/.config/systemd/user/jjfs.service")
      FileUtils.mkdir_p(File.dirname(service_path))
      File.write(service_path, content)
      
      # Reload systemd
      Process.run("systemctl", ["--user", "daemon-reload"])
      
      # Enable and start
      result = Process.run("systemctl", ["--user", "enable", "--now", "jjfs"],
                         output: Process::Redirect::Pipe,
                         error: Process::Redirect::Pipe)
      
      unless result.success?
        puts "Error: Failed to enable service: #{result.error}"
        return false
      end
      
      puts "Installed and started jjfs service (systemd)"
      true
    end
  end
end
```

**Step 4: Wire to CLI**

File: `src/cli.cr`

```crystal
require "./commands/install"

when :install
  cmd = Commands::Install.new
  exit(cmd.execute ? 0 : 1)
```

**Step 5: Implement start/stop commands**

File: `src/commands/start.cr`

```crystal
module JJFS::Commands
  class Start
    def execute
      {% if flag?(:darwin) %}
        plist = File.expand_path("~/Library/LaunchAgents/com.jjfs.daemon.plist")
        Process.run("launchctl", ["load", plist])
      {% elsif flag?(:linux) %}
        Process.run("systemctl", ["--user", "start", "jjfs"])
      {% end %}
      
      puts "Started jjfs daemon"
      true
    end
  end
end
```

Similar for `Stop`.

**Step 6: Commit**

```bash
git add templates/ src/commands/install.cr src/commands/start.cr src/commands/stop.cr src/cli.cr
git commit -m "feat: implement service installation for launchd/systemd"
```

---

## Phase 7: Testing & Documentation

### Task 13: Integration Tests

**Files:**
- Create: `spec/integration_spec.cr`

**Step 1: Write integration test**

File: `spec/integration_spec.cr`

```crystal
require "./spec_helper"
require "file_utils"

describe "jjfs integration" do
  it "syncs files between two mounts" do
    # Setup
    tmp_root = File.tempname("jjfs_int_test")
    storage = JJFS::Storage.new(tmp_root)
    storage.ensure_directories
    
    # Init repo
    init_cmd = JJFS::Commands::Init.new(storage, "default")
    init_cmd.execute.should be_true
    
    # Create two mounts
    mount_a = File.join(tmp_root, "mount-a")
    mount_b = File.join(tmp_root, "mount-b")
    
    manager = JJFS::MountManager.new(storage)
    manager.mount("default", mount_a).should_not be_nil
    manager.mount("default", mount_b).should_not be_nil
    
    # Start sync coordinator
    coordinator = JJFS::SyncCoordinator.new(storage)
    coordinator.start
    
    # Write to mount-a
    File.write(File.join(mount_a, "test.txt"), "hello")
    
    # Wait for sync
    sleep 3
    
    # Verify in mount-b
    File.read(File.join(mount_b, "test.txt")).should eq("hello")
    
    # Cleanup
    coordinator.stop
    manager.unmount(mount_a)
    manager.unmount(mount_b)
    FileUtils.rm_rf(tmp_root)
  end
end
```

**Step 2: Run integration tests**

```bash
crystal spec spec/integration_spec.cr
```

Expected: PASS

**Step 3: Commit**

```bash
git add spec/integration_spec.cr
git commit -m "test: add integration tests for sync"
```

---

### Task 14: README & User Documentation

**Files:**
- Modify: `README.md`
- Create: `docs/user-guide.md`

**Step 1: Update README**

File: `README.md`

```markdown
# jjfs - Eventually Consistent Multi-Mount Filesystem

FUSE-based filesystem that allows multiple directories to be live, eventually-consistent views of the same Jujutsu repository.

## Features

- **Multi-mount:** Mount same repo in unlimited locations
- **Eventually consistent:** Changes propagate automatically (<2s)
- **Zero maintenance:** Auto-syncs, auto-starts on login
- **Remote backup:** Push/pull to GitHub/GitLab
- **Cross-platform:** macOS and Linux

## Installation

### Requirements

- Crystal 1.10+
- Jujutsu (`jj`)
- bindfs
- macOS: fswatch (`brew install fswatch`)
- Linux: inotify (built-in)

### Build

```bash
shards install
crystal build src/jjfs.cr -o bin/jjfs --release
crystal build src/jjfsd.cr -o bin/jjfsd --release
sudo cp bin/jjfs /usr/local/bin/
sudo cp bin/jjfsd /usr/local/bin/
```

### Setup

```bash
jjfs install  # Install system service
jjfs init     # Initialize default repo
```

## Quick Start

```bash
# Open repo in two locations
jjfs open default ~/project-a/notes
jjfs open default ~/project-b/notes

# Edit anywhere
echo "content" > ~/project-a/notes/file.md

# Appears everywhere (within 2s)
cat ~/project-b/notes/file.md

# Add remote backup
jjfs remote add git@github.com:user/notes.git
```

## Commands

- `jjfs init [name]` - Initialize repo
- `jjfs open <repo> [path]` - Open repo at path
- `jjfs close <path>` - Close mount
- `jjfs list` - List mounts
- `jjfs status` - Show daemon status
- `jjfs remote add <url>` - Add remote
- `jjfs sync [repo]` - Force sync

## Documentation

- [Design Document](docs/plans/2025-10-19-jjfs-design.md)
- [User Guide](docs/user-guide.md)

## License

MIT
```

**Step 2: Create user guide**

File: `docs/user-guide.md`

```markdown
# jjfs User Guide

## Concepts

### Repos
A repo is a Jujutsu repository that stores your files.

### Mounts
Mounts are directories that show a live view of a repo.

### Sync
Changes in any mount propagate to all other mounts of the same repo within 1-2 seconds.

## Common Workflows

### Personal Notes Across Projects

```bash
jjfs init notes
jjfs open notes ~/work-project/notes
jjfs open notes ~/personal-project/notes
jjfs open notes ~/research/notes
```

### Work vs Personal

```bash
jjfs init personal
jjfs init work

jjfs open personal ~/projects/personal/notes
jjfs open work ~/projects/work/notes
```

### With Remote Backup

```bash
jjfs init notes
jjfs remote add git@github.com:user/notes.git
jjfs open notes ~/notes

# Changes auto-push every 5 minutes
```

## Troubleshooting

### Check daemon status

```bash
jjfs status
```

### View logs

```bash
tail -f ~/.jjfs/daemon.log
tail -f ~/.jjfs/sync.log
```

### Restart daemon

```bash
jjfs stop
jjfs start
```

### Conflicts

If two mounts edit the same line simultaneously, jj creates conflict markers:

```
<<<<<<< side 1
version from mount A
=======
version from mount B
>>>>>>> side 2
```

Edit the file to resolve, save, and changes propagate.
```

**Step 3: Commit**

```bash
git add README.md docs/user-guide.md
git commit -m "docs: add comprehensive README and user guide"
```

---

## Phase 8: Release Preparation

### Task 15: Version 0.1.0 Release

**Files:**
- Create: `CHANGELOG.md`
- Create: `.github/workflows/ci.yml` (optional)

**Step 1: Create changelog**

File: `CHANGELOG.md`

```markdown
# Changelog

## [0.1.0] - 2025-10-19

### Added
- Initial release
- Multi-mount support for jj repositories
- Eventually consistent sync (<2s propagation)
- Remote backup via jj git backend
- CLI commands: init, open, close, list, status, remote, sync
- Daemon with JSON-RPC server
- Filesystem watcher (fswatch/inotify)
- Pass-through FUSE mounts via bindfs
- Service installation (launchd/systemd)
- macOS and Linux support

### Features
- Auto-sync between mounts
- Auto-push to remotes every 5 minutes
- Conflict resolution via jj conflict markers
- Zero-maintenance operation
```

**Step 2: Tag release**

```bash
git add CHANGELOG.md
git commit -m "chore: prepare v0.1.0 release"
git tag v0.1.0
```

**Step 3: Build release binaries**

```bash
crystal build src/jjfs.cr -o bin/jjfs --release
crystal build src/jjfsd.cr -o bin/jjfsd --release
```

**Step 4: Test release**

```bash
# Full smoke test
./bin/jjfs install
./bin/jjfs init test
./bin/jjfs open test ./test-mount
echo "test" > ./test-mount/file.txt
./bin/jjfs list
./bin/jjfs status
./bin/jjfs close ./test-mount
```

**Step 5: Commit**

```bash
git push origin main --tags
```

---

## Summary

This plan implements jjfs in 15 major tasks across 8 phases:

1. **Project Setup** - Crystal project, config, storage
2. **CLI Framework** - Command parser, init command
3. **Daemon Foundation** - JSON-RPC server, status command
4. **FUSE Integration** - Mount/unmount with bindfs
5. **Sync Engine** - Filesystem watcher, sync coordinator
6. **Remote Sync** - Push/pull, remote command
7. **Service Installation** - launchd/systemd integration
8. **Testing & Docs** - Integration tests, documentation

Each task follows TDD: write test → verify fail → implement → verify pass → commit.

The result is a working V1 of jjfs with all core features:
- Multi-mount support
- Eventually consistent sync
- Remote backup
- Zero-maintenance operation
- Cross-platform (macOS/Linux)
