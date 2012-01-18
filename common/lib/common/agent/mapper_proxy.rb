#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RightScale

  # This class allows sending requests to agents without having to run a local mapper.
  # It is used by Actor.request which is used by actors that need to send requests to remote agents.
  # All requests go through the mapper for security purposes.
  class MapperProxy

    include StatsHelper

    # Minimum number of seconds between restarts of the inactivity timer
    MIN_RESTART_INACTIVITY_TIMER_INTERVAL = 60

    # Number of seconds to wait for ping response from a mapper when checking connectivity
    PING_TIMEOUT = 30

    # (EM::Timer) Timer while waiting for mapper ping response
    attr_accessor :pending_ping

    # (Hash) Pending requests; key is request token and value is hash with :result_handler value being a block
    attr_accessor :pending_requests

    # (String) Identity of the agent using the mapper proxy
    attr_reader :identity

    # Accessor for use by actor
    #
    # === Return
    # (MapperProxy):: This mapper proxy instance if defined, otherwise nil
    def self.instance
      @@instance if defined?(@@instance)
    end

    # Initialize mapper proxy
    #
    # === Parameters
    # agent(Agent):: Agent using this mapper proxy; uses its identity, broker, and following options:
    #   :exception_callback(Proc):: Callback with following parameters that is activated on exception events:
    #     exception(Exception):: Exception
    #     message(Packet):: Message being processed
    #     mapper(Agent):: Reference to agent
    #   :persist(Symbol):: Instructions for the AMQP broker for saving messages to persistent storage
    #     so they aren't lost when the broker is restarted:
    #       none - do not persist any messages
    #       all - persist all push and request messages
    #       push - only persist one-way request messages
    #       request - only persist two-way request messages and their associated result
    #     Can be overridden on a per-message basis using the persistence option.
    #   :ping_interval(Integer):: Minimum number of seconds since last message receipt to ping the mapper
    #     to check connectivity, defaults to 0 meaning do not ping
    #   :retry_timeout(Numeric):: Maximum number of seconds to retry request before give up
    #   :retry_interval(Numeric):: Number of seconds before initial request retry, increases exponentially
    #   :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict agents to themselves
    #   :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #     to do requested work on EM defer thread and all else, such as pings on main thread
    def initialize(agent)
      @agent = agent
      @identity = @agent.identity
      @options = @agent.options || {}
      @broker = @agent.broker
      @secure = @options[:secure]
      @persist = @options[:persist]
      @single_threaded = @options[:single_threaded]
      @retry_timeout = nil_if_zero(@options[:retry_timeout])
      @retry_interval = nil_if_zero(@options[:retry_interval])
      @ping_interval = @options[:ping_interval] || 0

      # Only to be accessed from primary thread
      @pending_requests = {}
      @pending_ping = nil

      reset_stats
      @last_received = 0
      restart_inactivity_timer if @ping_interval > 0
      @@instance = self
    end

    # Update the time this agent last received a request or response message
    # and restart the inactivity timer thus deferring the next connectivity check
    #
    # === Return
    # true:: Always return true
    def message_received
      if @ping_interval > 0
        now = Time.now.to_i
        if (now - @last_received) > MIN_RESTART_INACTIVITY_TIMER_INTERVAL
          @last_received = now
          restart_inactivity_timer
        end
      end
    end

    # Send request to given agent through the mapper
    #
    # === Parameters
    # type(String):: The dispatch route for the request
    # payload(Object):: Payload to send.  This will get marshalled en route.
    #
    # === Block
    # Optional block used to process result
    #
    # === Return
    # true:: Always return true
    def request(type, payload = '', opts = {}, &blk)
      raise "Mapper proxy not initialized" unless identity
      token = AgentIdentity.generate
      method = type.split('/').last
      received_at = @requests.update(method, token)
      # Using next_tick to ensure on primary thread since using @pending_requests
      EM.next_tick do
        begin
          request = Request.new(type, payload, opts)
          request.from = @identity
          request.token = token
          request.persistent = opts.key?(:persistent) ? opts[:persistent] : ['all', 'request'].include?(@persist)
          @pending_requests[token] = {:result_handler => blk, :receive_time => received_at}
          request_with_retry(request, token)
        rescue Exception => e
          RightLinkLog.error("Failed to send #{type} request: #{e}\n" + e.backtrace.join("\n"))
          @exceptions.track("request", e, request)
        end
      end
      true
    end

    # Send push to given agent through the mapper
    #
    # === Parameters
    # type(String):: The dispatch route for the request
    # payload(Object):: Payload to send.  This will get marshalled en route.
    #
    # === Return
    # true:: Always return true
    def push(type, payload = '', opts = {})
      raise "Mapper proxy not initialized" unless identity
      method = type.split('/').last
      @requests.update(method)
      push = Push.new(type, payload, opts)
      push.from = @identity
      push.token = AgentIdentity.generate
      push.persistent = opts.key?(:persistent) ? opts[:persistent] : ['all', 'push'].include?(@persist)
      publish(push)
      true
    end

    # Delete pending request whose results are no longer needed
    # Also delete any associated retry requests
    #
    # === Parameters
    # token(String):: Request token
    #
    # === Return
    # true:: Always return true
    def purge(token)
      handler = @pending_requests.delete(token)
      if handler
        @requests.finish(handler[:receive_time], token)
        parent = handler[:retry_parent]
      end
      @pending_requests.reject! { |k, v| k == parent || v[:retry_parent] == parent } if parent
      true
    end

    # Handle result which may be final or part of a multicast sequence
    # Use defer thread instead of primary if not single threaded, consistent with dispatcher,
    # so that all shared data is accessed from the same thread
    # Do callback if there is an exception, consistent with agent identity queue handling
    # Only to be called from primary thread
    #
    # === Parameters
    # result(Result):: Packet received as result of request
    #
    # === Return
    # true:: Always return true
    def handle_result(result)
      if handler = @pending_requests[result.token]
        multicast = if (r = OperationResult.from_results(result)) && r.multicast?
          handler[:multicast] = r.content.size
        else
          handler[:multicast] -= 1 if handler[:multicast]
        end

        purge(result.token) if multicast.nil? || multicast == 0

        if handler[:result_handler]
          EM.__send__(@single_threaded ? :next_tick : :defer) do
            begin
              handler[:result_handler].call(result)
            rescue Exception => e
              RightLinkLog.error("Failed processing result #{result.to_s([])}: #{e}\n" + e.backtrace.join("\n"))
              @exceptions.track("result", e, result)
            end
          end
        end
      else
        RightLinkLog.debug("No pending request for result #{result.to_s([])}")
      end
      true
    end

    # Get age of youngest pending request
    #
    # === Return
    # age(Integer|nil):: Age in seconds of youngest request, or nil if no pending requests
    def request_age
      time = Time.now
      age = nil
      @pending_requests.each_value do |request|
        seconds = time - request[:receive_time]
        age = seconds.to_i if age.nil? || seconds < age
      end
      age
    end

    # Create displayable dump of unfinished request information
    # Truncate list if there are more than 50 requests
    #
    # === Return
    # info(Array(String)):: Receive time and token for each request in descending time order
    def dump_requests
      info = []
      @pending_requests.each do |token, request|
        info << "#{request[:receive_time].localtime} <#{token}>"
      end
      info.sort.reverse
      info = info[0..49] + ["..."] if info.size > 50
      info
    end

    # Get mapper proxy statistics
    #
    # === Parameters
    # reset(Boolean):: Whether to reset the statistics after getting the current ones
    #
    # === Return
    # stats(Hash):: Current statistics:
    #   "exceptions"(Hash|nil):: Exceptions raised per category, or nil if none
    #     "total"(Integer):: Total exceptions for this category
    #     "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
    #   "pings"(Hash|nil):: Request activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown for "success" vs. "timeout", or nil if none
    #   "requests"(Hash|nil):: Request activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown per request type, or nil if none
    #   "requests pending"(Integer|nil):: Number of requests waiting for response, or nil if none
    #   "response time"(Float):: Average number of seconds to respond to a request recently
    #   "retries"(Hash|nil):: Request activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown per request type, or nil if none
    #   "retry timeouts"(Integer|nil):: Number of requests that failed after maximum number of retries,
    #     or nil if none
    def stats(reset = false)
      stats = {
        "exceptions"       => @exceptions.stats,
        "pings"            => @pings.all,
        "requests"         => @requests.all,
        "requests pending" => nil_if_zero(@pending_requests.size),
        "response time"    => @requests.avg_duration,
        "retries"          => @retries.all,
        "retry timeouts"   => nil_if_zero(@retry_timeouts)
      }
      reset_stats if reset
      stats
    end

    protected

    # Reset dispatch statistics
    #
    # === Return
    # true:: Always return true
    def reset_stats
      @pings = ActivityStats.new
      @retries = ActivityStats.new
      @requests = ActivityStats.new
      @exceptions = ExceptionStats.new(@agent, @options[:exception_callback])
      @retry_timeouts = 0
      true
    end

    # Send request with one or more retries if do not receive a result in time
    # Send timeout result if reach retry timeout limit
    # Use exponential backoff for retry spacing
    #
    # === Parameters
    # request(Request):: Request to be sent
    # parent(String):: Token for original request
    # count(Integer):: Number of retries so far
    # multiplier(Integer):: Multiplier for retry interval for exponential backoff
    # elapsed(Integer):: Elapsed time in seconds since this request was first attempted
    #
    # === Return
    # true:: Always return true
    def request_with_retry(request, parent, count = 0, multiplier = 1, elapsed = 0)
      ids = publish(request)

      if @retry_interval && @retry_timeout && parent && !ids.empty?
        interval = @retry_interval * multiplier
        EM.add_timer(interval) do
          begin
            if (handler = @pending_requests[parent]) && handler[:multicast].nil?
              count += 1
              elapsed += interval
              if elapsed <= @retry_timeout
                request.tries << request.token
                request.token = AgentIdentity.generate
                @pending_requests[parent][:retry_parent] = parent if count == 1
                @pending_requests[request.token] = @pending_requests[parent]
                request_with_retry(request, parent, count, multiplier * 4, elapsed)
                @retries.update(request.type.split('/').last)
              else
                RightLinkLog.warn("RE-SEND TIMEOUT after #{elapsed} seconds for #{request.to_s([:tags, :target, :tries])}")
                result = OperationResult.timeout("Timeout after #{elapsed} seconds and #{count} attempts")
                handle_result(Result.new(request.token, request.reply_to, result, @identity))
                @retry_timeouts += 1
              end
              check_connection(ids.first) if count == 1
            end
          rescue Exception => e
            RightLinkLog.error("Failed retry for #{request.token}: #{e}\n" + e.backtrace.join("\n"))
            @exceptions.track("retry", e, request)
          end
        end
      end
      true
    end

    # Check whether broker connection is usable by pinging a mapper
    # The connection is declared unusable if ping does not respond in PING_TIMEOUT seconds
    # The request is ignored if already checking a connection
    # Only to be called from primary thread
    #
    # === Parameters
    # id(String):: Identity of specific broker to use to send ping, defaults to any
    #   currently connected broker
    #
    # === Return
    # true:: Always return true
    def check_connection(id = nil)
      unless @pending_ping || (id && !@broker.connected?(id))
        @pending_ping = EM::Timer.new(PING_TIMEOUT) do
          begin
            @pings.update("timeout")
            @pending_ping = nil
            RightLinkLog.warn("Mapper ping via broker #{id} timed out after #{PING_TIMEOUT} seconds, attempting to reconnect")
            host, port, alias_id, priority = @broker.identity_parts(id)
            @agent.connect(host, port, alias_id, priority, force = true)
          rescue Exception => e
            RightLinkLog.error("Failed to reconnect to broker #{id}: #{e}\n" + e.backtrace.join("\n"))
            @exceptions.track("ping timeout", e)
          end
        end

        handler = lambda do |_|
          begin
            if @pending_ping
              @pings.update("success")
              @pending_ping.cancel
              @pending_ping = nil
            end
          rescue Exception => e
            RightLinkLog.error("Failed to cancel mapper ping: #{e}\n" + e.backtrace.join("\n"))
            @exceptions.track("cancel ping", e)
          end
        end

        request = Request.new("/mapper/ping", nil, {:from => @identity, :token => AgentIdentity.generate})
        @pending_requests[request.token] = {:result_handler => handler, :receive_time => Time.now}
        ids = [id] if id
        id = publish(request, ids).first
      end
      true
    end

    # Publish request
    #
    # === Parameters
    # request(Push|Request):: Packet to be sent
    # ids(Array):: Identity of specific brokers to choose from
    #
    # === Return
    # ids(Array):: Identity of brokers published to
    def publish(request, ids = nil)
      begin
        exchange = {:type => :fanout, :name => "request", :options => {:durable => true, :no_declare => @secure}}
        ids = @broker.publish(exchange, request, :persistent => request.persistent,
                              :log_filter => [:tags, :target, :multicast, :tries, :persistent], :brokers => ids)
      rescue HA_MQ::NoConnectedBrokers => e
        RightLinkLog.error("Failed to publish request #{request.trace}: #{e}")
        ids = []
      rescue Exception => e
        RightLinkLog.error("Failed to publish request #{request.trace}: #{e}\n" + e.backtrace.join("\n"))
        @exceptions.track("publish", e, request)
        ids = []
      end
      ids
    end

    # Start timer that waits for inactive messaging period to end before checking connectivity
    #
    # === Return
    # true:: Always return true
    def restart_inactivity_timer
      @timer.cancel if @timer
      @timer = EM::Timer.new(@ping_interval) do
        begin
          check_connection
        rescue Exception => e
          RightLinkLog.error("Failed connectivity check: #{e}\n" + e.backtrace.join("\n"))
        end
      end
      true
    end

    # Convert value to nil if equals 0
    #
    # === Parameters
    # value(Integer|nil):: Value to be converted
    #
    # === Return
    # (Integer|nil):: Converted value
    def nil_if_zero(value)
      if !value || value == 0 then nil else value end
    end

  end # MapperProxy

end # RightScale