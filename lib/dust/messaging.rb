require 'colorize'

module Dust

  class Messages
    attr_reader :current_recipe

    def initialize
      @store = {}
    end

    def add(msg, options = {})
      m = Message.new(msg, options)

      if @recipe
        @store[@current_recipe] ||= []
        @store[@current_recipe] << m
      else
        @store['_node'] ||= []
        @store['_node'] << m
      end

      m
    end
    
    def start_recipe(name)
      @current_recipe = name
    end
  end

  class Message

    def initialize(msg, options = {})
      # autoflush
      $stdout.sync = true

      # merge default options
      @options = { :quiet => false, :indent => 1 }.merge options

      @msg = msg
      print indent + @msg
    end

    def ok
      puts ' [ ok ]'.green
      true
    end

    def warning
      puts ' [ warning ]'.yellow
      true
    end

    def failed
      puts ' [ failed ]'.red
      false
    end

    def parse_result(ret)
      return ok if ret == 0 or ret.is_a? TrueClass
      failed
    end

    # prints stdout in grey and stderr in red (if existend)
    def print_output(ret)
      puts indent + '  ' + ret[:stdout].chomp.green unless ret[:stdout].empty?
      puts indent + '  ' + ret[:stderr].chomp.red unless ret[:stderr].empty?
    end


    private

    # indent according to @options[:indent]
    # indent 0
    #  - indent 1
    #    - indent 2
    def indent
      return '' if @options[:quiet] or @options[:indent] == 0
      ' ' + '  ' * (@options[:indent] - 1) + '- '
    end
  end
end
