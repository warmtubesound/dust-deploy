# include all extensions
Dir["#{File.dirname(__FILE__)}/server/*.rb"].each { |file| require file }

module Dust
  class Server
    attr_reader :messages

    def default_options options = {}
      { :quiet => false, :indent => 1 }.merge options
    end

    def initialize node
      @node = node
      @node['user'] ||= 'root'
      @node['port'] ||= 22
      @node['password'] ||= ''
      @node['sudo'] ||= false

      @messages = Messages.new
    end

    private

    def method_missing method, *args, &block
      # make server nodeibutes accessible via server.nodeibute
      if @node[method.to_s]
        @node[method.to_s]

      # and as server['nodeibute']
      elsif @node[args.first]
        @node[args.first]

      # default to super
      else
        super
      end
    end
  end
end
