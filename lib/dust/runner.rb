require 'thor/runner'
require 'thor/util'
require 'yaml'
require 'erb'
require 'fileutils'
require 'ipaddress'
require 'colorize'

module  Dust
  class Runner < Thor::Runner

    default_task :list
    check_unknown_options!

    # default options for all tasks
    def self.default_options
      method_option 'yaml', :type => :string, :desc => 'use only this server.yaml'
      method_option 'filter', :type => :hash, :desc => 'only deploy to these hosts (e.g. environment:staging)'
      method_option 'proxy', :type => :string, :desc => 'socks proxy to use'
      method_option 'parallel', :type => :boolean, :desc => 'deploy to all hosts at the same time using threads'
      method_option 'summary', :type => :string, :desc => 'print summary of all events (all, warning, failed)'
    end

    def self.recipe_options
      method_option 'recipes', :type => :array, :desc => 'only deploy these recipes'
    end


    desc 'deploy', 'deploy all recipes to the node(s) specified in server.yaml or to all nodes defined in ./nodes/'
    default_options
    recipe_options
    method_option 'restart', :type => :boolean, :desc => 'restart services after deploy'
    method_option 'reload', :type => :boolean, :desc => 'reload services after deploy'

    def deploy
      return unless check_dust_dir
      initialize_thorfiles
      puts 'no servers match this filter'.red if load_servers.empty?

      # set global variables
      $summary = options['summary']
      $parallel = options['parallel']
      $summary = 'all' if $parallel and not $summary

      threads = []
      @nodes.each_with_index do |node, i|
        if $parallel
          threads[i] = Thread.new do
            Thread.current['hostname'] = node['hostname'] if run_recipes(node, 'deploy')
          end
        else
          run_recipes(node, 'deploy')
        end
      end

      if $parallel
        print 'waiting for servers: '
        threads.each do |t|
          t.join # wait for thread
          print t['hostname'].blue + ' ' if t['hostname']
        end
        puts
      end

      display_summary($summary) if $summary
    end


    desc 'status', 'display status of recipes specified by filter'
    default_options
    recipe_options

    def status
      return unless check_dust_dir
      initialize_thorfiles
      puts 'no servers match this filter'.red if load_servers.empty?

      # set global variables
      $summary = options['summary']
      $parallel = options['parallel']
      $summary = 'all' if $parallel and not $summary

      threads = []
      @nodes.each_with_index do |node, i|
        if $parallel
          threads[i] = Thread.new do
            Thread.current['hostname'] = node['hostname'] if run_recipes(node, 'status')
          end
        else
          run_recipes(node, 'status')
        end
      end

      if $parallel
        print 'waiting for servers: '
        threads.each do |t|
          t.join # wait for thread
          print t['hostname'].blue + ' ' if t['hostname']
        end
        puts
      end

      display_summary($summary) if $summary
    end


    desc 'system_update', 'perform a full system upgrade (using aptitude, emerge, yum)'
    default_options

    def system_update
      return unless check_dust_dir
      initialize_thorfiles
      puts 'no servers match this filter'.red if load_servers.empty?

      # set global variables
      $summary = options['summary']
      $parallel = options['parallel']
      $summary = 'all' if $parallel and not $summary

      threads = []
      @nodes.each_with_index do |node, i|
        if $parallel
          threads[i] = Thread.new do
            run_system_update(node)
            Thread.current['hostname'] = node['hostname']
          end
        else
          run_system_update(node)
        end
      end

      if $parallel
        print 'waiting for servers: '
        threads.each do |t|
          t.join # wait for thread
          print t['hostname'].blue + ' ' if t['hostname']
        end
        puts
      end

      display_summary($summary) if $summary
    end


    desc 'exec <command>', 'run a command on the server'
    default_options

    def exec cmd, yaml=''
      return unless check_dust_dir
      initialize_thorfiles
      puts 'no servers match this filter'.red if load_servers.empty?

      # set global variables
      $summary = options['summary']
      $parallel = options['parallel']
      $summary = 'all' if $parallel and not $summary

      threads = []
      @nodes.each_with_index do |node, i|
        if $parallel
          threads[i] = Thread.new do
            run_exec(node, cmd)
            Thread.current['hostname'] = node['hostname']
          end
        else
          run_exec(node, cmd)
        end
      end

      if $parallel
        print 'waiting for servers: '
        threads.each do |t|
          t.join # wait for thread
          print t['hostname'].blue + ' ' if t['hostname']
        end
        puts
      end

      display_summary($summary) if $summary
    end


    # creates directory skeleton for a dust setup
    desc 'new <name>', 'creates a dust directory skeleton for your network'
    def new(name)
      puts "spawning new dust directory skeleton with examples into '#{name}.dust'"
      FileUtils.cp_r(File.dirname(__FILE__) + '/examples', "#{name}.dust")
    end

    desc 'version', 'displays version number'
    def version
      puts "dust-deploy-#{Dust::VERSION}, running on ruby-#{RUBY_VERSION}"
    end


    private

    def check_dust_dir
      if Dir.pwd.split('.').last != 'dust'
        puts 'current directory does not end with .dust, are you in your dust directory?'.red
        puts "try running 'dust new mynetwork' to let me create one for you with tons of examples!\n"
        return false
      end

      unless File.directory?('./nodes')
        puts 'could not find \'nodes\' folder in your dust directory. cannot continue.'.red
        return false
      end

      true
    end

    # run specified recipes in the given context
    # returns false if no recipes where found
    # true if recipes were run (doesn't indicate, whether the run was sucessful or not)
    def run_recipes(node, context)
      # skip this node if there are no recipes found
      return false unless node['recipes']

      recipes = generate_recipes(node, context)

      # skip this node unless we're actually having recipes to cook
      return false if recipes.empty?

      # connect to server
      node['server'] = Server.new(node)
      return true unless node['server'].connect

      # runs the method with the recipe name, defined and included in recipe/*.rb
      # call recipes for each recipe that is defined for this node
      recipes.each do |recipe, config|
        send(recipe, 'prepare', node['server'], recipe, context, config, options)
      end

      node['server'].disconnect
      true
    end

    def run_system_update(node)
      node['server'] = Server.new(node)
      return unless node['server'].connect
      node['server'].system_update
      node['server'].disconnect
    end

    def run_exec(node, cmd)
      node['server'] = Server.new(node)
      return unless node['server'].connect
      node['server'].exec(cmd, :live => true)
      node['server'].disconnect
    end

    # generate list of recipes for this node
    def generate_recipes(node, context)
      recipes = {}
      node['recipes'].each do |recipe, config|

        # in case --recipes was set, skip unwanted recipes
        next unless options['recipes'].include?(recipe) if options['recipes']

        # skip disabled recipes
        next if config == 'disabled' or config.is_a? FalseClass

        # check if method and thor task actually exist
        k = Thor::Util.find_by_namespace(recipe)
        next unless k
        next unless k.method_defined?(context)

        recipes[recipe] = config
      end
      recipes
    end

    def display_summary(level)
      puts "\n\n------------------------------ SUMMARY ------------------------------".red unless $parallel

      @nodes.each do |node|
        next unless node['server']

        messages = node['server'].messages.collect(level)
        next if messages.empty?

        node['server'].messages.print_hostname_header(node['hostname'])

        # display non-recipe messages first
        msgs = messages.delete '_node'
        msgs.each { |m| print m } if msgs

        # display messages from recipes
        messages.each do |recipe, msgs|
          node['server'].messages.print_recipe_header(recipe)
          msgs.each { |m| print m }
        end
      end
    end

    # overwrite thorfiles to look for tasks in the recipes directories
    def thorfiles(relevant_to=nil, skip_lookup=false)
      Dir[File.dirname(__FILE__) + '/recipes/*.rb'] | Dir['recipes/*.rb']
    end

    # loads servers
    def load_servers
      @nodes = []

      # if the argument is empty, load all yaml files in the ./nodes/ directory
      # if the argument is a directory, load yaml files in this directory
      # if the argument is a file, load the file.
      if options['yaml']
        if File.directory?(options['yaml'])
          yaml_files = Dir["#{options['yaml']}/**/*.yaml"]
        elsif File.exists?(options['yaml'])
          yaml_files = options['yaml']
        end
      else
        yaml_files = Dir['./nodes/**/*.yaml']
      end

      unless yaml_files
        puts "#{yaml} doesn't exist. exiting.".red
        exit
      end

      yaml_files.to_array.each do |file|
        node = YAML.load ERB.new( File.read(file), nil, '%<>').result

        # if the file is empty, just skip it
        next unless node

        # if there is not hostname field in the yaml file,
        # treat this node file as a template, and skip to the next one
        next unless node['hostname']

        # look for the inherits field in the yaml file,
        # and merge the templates recursively into this node
        if node['inherits']
          inherited = {}
          node.delete('inherits').each do |file|
            template = YAML.load ERB.new( File.read("./nodes/#{file}.yaml"), nil, '%<>').result
            inherited.deep_merge! template
          end
          node = inherited.deep_merge node
        end

        # if more than one hostname is specified, create a node
        # with the same settings for each hostname
        node['hostname'].to_array.each do |hostname|
          n = node.clone

          # overwrite hostname with single hostname (in case there are multiple)
          n['hostname'] = hostname

          # create a new field with the fully qualified domain name
          n['fqdn'] = hostname

          # if hostname is a valid ip address, don't add domain
          # so we can connect via ip address only
          unless IPAddress.valid?(hostname)
            n['fqdn'] += '.' + n['domain'] if n['domain']
          end

          # pass command line proxy option
          n['proxy'] = options['proxy'] if options['proxy']

          # add this node to the global node array
          @nodes.push(n) unless filtered?(n)
        end
      end
    end

    # checks if this node was filtered out by command line argument
    # e.g. --filter environment:staging filters out all machines but
    # those in the environment staging
    def filtered?(node)

      # if filter is not specified, instantly return false
      return false unless options['filter']

      # remove items if other filter arguments don't match
      options['filter'].each do |k, v|
        next unless v # skip empty filters

        # filter if this node doesn't even have the attribute
        return true unless node[k]

        # allow multiple filters of the same type, divided by ','
        # e.g. --filter environment:staging,production
        return true unless v.split(',').include? node[k]
      end

      # no filter matched, so this host is not filtered.
      false
    end
  end
end
