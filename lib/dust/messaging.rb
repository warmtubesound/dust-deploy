require 'colorize'

module Dust

  class Messages
    attr_reader :current_recipe

    def initialize
      @store = {}
    end

    def add(msg, options = {})
      m = Message.new(msg, options)

      if @current_recipe
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

    def collect(level = 'all')
      case level
      when 'all'
        l = [ 'none', 'ok', 'warning', 'failed' ]
      when 'warning'
        l = [ 'warning', 'failed' ]
      when 'failed'
        l = [ 'failed' ]
      end

      errors = {}
      @store.each do |recipe, messages|
        messages.each do |msg|
          if l.include? msg.status
            errors[recipe] ||= []
            errors[recipe] << msg.text
          end
        end
      end

      errors
    end

  end

  class Message
    attr_reader :text, :status

    def initialize(msg = '', options = {})
      # merge default options
      @options = { :quiet => false, :indent => 1 }.merge options

      # autoflush
      $stdout.sync = true

      # just return if quiet mode is on
      unless @options[:quiet]
        # default status is 'message'
        @status = 'none'

        @text = indent + msg
        print @text unless $summary
      end
    end

    def ok(msg = '')
      unless @options[:quiet]
        @text << msg + ' [ ok ]'.green + "\n"
        puts msg + ' [ ok ]'.green unless $summary
        @status = 'ok'
      end

      true
    end

    def warning(msg = '')
      unless @options[:quiet]
        @text << msg + ' [ warning ]'.yellow + "\n"
        puts msg + ' [ warning ]'.yellow unless $summary
        @status = 'warning'
      end

      true
    end

    def failed(msg = '')
      unless @options[:quiet]
        @text << msg + ' [ failed ]'.red + "\n"
        puts msg + ' [ failed ]'.red unless $summary
        @status = 'failed'
      end

      false
    end

    def parse_result(ret)
      return ok if ret == 0 or ret.is_a? TrueClass
      failed
    end

    # prints stdout in grey and stderr in red (if existend)
    def print_output(ret)
      @text << indent + ret[:stdout].chomp.green + "\n" unless ret[:stdout].empty?
      @text << indent + ret[:stderr].chomp.red + "\n" unless ret[:stderr].empty?

      print @text unless $summary
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
