#require 'rufus/tokyo/tyrant'

module Rack
  module Session
    class RufusTyrant < Abstract::ID

      attr_reader :pool

      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge :tyrant_server => "localhost:1978"

      def initialize(app, options = {})
        super
        @mutex = Mutex.new
        @host, @port = (options[:tyrant_server] || @default_options[:tyrant_server]).split(':')
        @pool ||= Rufus::Tokyo::Tyrant.new(@host, @port.to_i)
      end

      private

      def get_session(env, sid)

        if sid && session = @pool[sid]
          session = Marshal.load(@pool[sid]) rescue session
        end
          # DANGER ! session is not instantiated if sid is nil or false

        @mutex.lock if env['rack.multithread']

        unless sid && session
          env['rack.errors'].puts("Session '#{sid.inspect}' not found, initializing...") if $VERBOSE and not sid.nil?
          session = {}
          sid = generate_sid
          ret = @pool[sid] = Marshal.dump(session)
          raise "Session collision on '#{sid.inspect}'" unless ret
        end
        session.instance_variable_set('@old', {}.merge(session))

        return [sid, session]

      rescue Exception => e

        return [nil,  {}]

      ensure
        @mutex.unlock if env['rack.multithread']
      end

      def set_session(env, sid, new_session, options)

        @mutex.lock if env['rack.multithread']

        #if session = @pool[sid]
        #  session = Marshal.load(session) rescue session
        #end
          # why bother ? session is not used at all !

        if options[:renew] || options[:drop]
          @pool.delete sid
          return false if options[:drop]
          sid = generate_sid
          @pool[sid] = ""
        end
        old_session = new_session.instance_variable_get('@old') || {}
        session = new_session
        @pool[sid] = options && options[:raw] ? session : Marshal.dump(session)
        return sid

      rescue Exception => e
        warn "#{self} is unable to find server, error: #{e}"
        warn $!.inspect
      ensure
        @mutex.unlock if env['rack.multithread']
      end

      def generate_sid
        loop do
          sid = super
          return sid unless @pool[sid]
        end
      end

    end

  end

end
