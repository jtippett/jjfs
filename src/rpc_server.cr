require "json"
require "./storage"

module JJFS
  class RPCServer
    def initialize(@storage : Storage, @sync_coordinator : SyncCoordinator? = nil)
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
