module Rack
  module Session
    class Tokyo < Abstract::ID
      attr_reader :mutex, :pool
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge :tyrant_server => "localhost:1978"

      def initialize(app, options = {})
        # Support old :expires option
        #options[:expire_after] ||= options[:expires]
        super
        @mutex = Mutex.new
        # @default_options = {        #   :namespace => 'rack:session',        # }.merge(@default_options)
        host, port = *@default_options[:tyrant_server].split(":") # @default_options)        #options[:cache] ||
        begin
          @pool =  Rufus::Tokyo::Tyrant.new(host, port.to_i)
        rescue => e
          "No server avaiable or #{e}"
        end
        # unless @pool.servers.any? { |s| s.alive? }
        #   raise "#{self} unable to find server during initialization."
        # end
      end

      def generate_sid
        loop do
          sid = super
          break sid unless @pool[sid]
        end
      end

      private
      def get_session(env, sid)
        session = Marshal.load(@pool[sid]) if sid && sid != "" #sid ||= generate_sid
        @mutex.lock if env['rack.multithread']
        unless sid and session
          env['rack.errors'].puts("Session '#{sid.inspect}' not found, initializing...") if $VERBOSE and not sid.nil?
          session = {}
          sid = generate_sid
          ret = @pool[sid] = Marshal.dump(session)
          raise "Session collision on '#{sid.inspect}'" unless ret
        end
        session.instance_variable_set('@old', {}.merge(session))
        return [sid, session]
      rescue => e
        session = {}
      ensure
        @mutex.unlock if env['rack.multithread']
      end

      def set_session(env, sid, new_session, options)
        @mutex.lock if env['rack.multithread']
        session = Marshal.load(@pool[sid]) rescue {}
        if options[:renew] or options[:drop]
          @pool.delete sid
          return false if options[:drop]
          sid = generate_sid
          @pool[sid] = 0
        end
        old_session = new_session.instance_variable_get('@old') || {}
        session = merge_sessions sid, old_session, new_session, session
        @pool[sid] = Marshal.dump(session) #, options])
        return sid
      rescue => e
        warn "#{self} is unable to find server. #{e}"
        warn $!.inspect
        return false
      ensure
        @mutex.unlock if env['rack.multithread']
      end

      def merge_sessions(sid, old, new, cur=nil)
        cur ||= {}
        unless Hash === old and Hash === new
          warn 'Bad old or new sessions provided.'
          return cur
        end

        delete = old.keys - new.keys
        warn "//@#{sid}: dropping #{delete*','}" if $DEBUG and not delete.empty?
        delete.each{|k| cur.delete k }

        update = new.keys.select{|k| new[k] != old[k] }
        warn "//@#{sid}: updating #{update*','}" if $DEBUG and not update.empty?
        update.each{|k| cur[k] = new[k] }

        cur
      end

    end

  end

end
