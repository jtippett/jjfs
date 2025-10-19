require "socket"
require "./storage"
require "./rpc_server"
require "./sync_coordinator"
require "./remote_syncer"

module JJFS
  class Daemon
    @running = false
    @server : UNIXServer?
    @sync_coordinator : SyncCoordinator?
    @remote_syncer : RemoteSyncer?

    def initialize(@storage : Storage)
    end

    def start
      @storage.ensure_directories
      acquire_lock

      @running = true
      @server = UNIXServer.new(@storage.socket_path)

      puts "jjfsd started, listening on #{@storage.socket_path}"

      # Start sync coordinator
      @sync_coordinator = SyncCoordinator.new(@storage)
      @sync_coordinator.try &.start

      # Start remote syncer
      @remote_syncer = RemoteSyncer.new(@storage)
      @remote_syncer.try &.start

      rpc = RPCServer.new(@storage, @sync_coordinator)

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
      @sync_coordinator.try &.stop
      @remote_syncer.try &.stop
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
