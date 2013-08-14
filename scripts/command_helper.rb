module RightScale
  class CommandHelper
    # Creates a command client and sends the given payload.
    #
    # === Parameters
    # @param [Hash] cmd as a payload hash
    # @param [TrueClass, FalseClass] verbose flag
    # @param [TrueClass, FalseClass] timeout or nil
    #
    # === Block
    # @yield [response] callback for response
    # @yieldparam response [Object] response of any type
    def self.send_command(cmd, verbose, timeout)
      config_options = ::RightScale::AgentConfig.agent_options('instance')
      listen_port = config_options[:listen_port]
      raise ::ArgumentError.new('Could not retrieve agent listen port') unless listen_port
      client = ::RightScale::CommandClient.new(listen_port, config_options[:cookie])
      result = nil
      callback = Proc.new do |res|
        result = res
        yield res if block_given?
      end
      client.send_command(cmd, verbose, timeout, &callback)
      result
    end

    def self.serialize_operation_result(res)
      command_serializer = ::RightScale::Serializer.new
      ::RightScale::OperationResult.from_results(command_serializer.load(res))
    end
  end
end