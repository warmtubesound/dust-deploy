class Redis < Recipe
  desc 'redis:deploy', 'installs and configures redis key-value store'
  def deploy
    @node.install_package 'redis-server'
    @node.write '/etc/redis/redis.conf', generate_redis_conf
    @node.restart_service 'redis-server' if @options.restart
  end

  desc 'redis:status', 'displays redis-cli info'
  def status
    return false unless @node.package_installed? 'redis-server'
    msg = @node.messages.add('running "redis-cli info"')
    ret = @node.exec 'redis-cli info'
    msg.parse_result(ret[:exit_code])

    @node.messages.add(ret[:stdout], :indent => 0) unless ret[:stdout].empty?
  end
  
  
  private
  
  # default configuration variables for ubuntu
  # if you use a different os, you may adapt these
  # listens on all interfaces per default
  def default_config
    { 'daemonize' => 'yes',
      'port' => 6379,
      'timeout' => 300,
      'loglevel' => 'notice',
      'databases' => 16,
      'save' => [ '900 1', '300 10', '60 10000' ],
      'rdbcompression' => 'yes',
      'dbfilename' => 'dump.rdb',
      'slave-serve-stale-data' => 'yes',
      'appendonly' => 'no',
      'appendfsync' => 'everysec',
      'no-appendfsync-on-rewrite' => 'no',
      'vm-enabled' => 'no',
      'vm-max-memory' => 0,
      'vm-page-size' => 32,
      'vm-pages' => 134217728,
      'vm-max-threads' => 4,
      'hash-max-zipmap-entries' => 512,
      'hash-max-zipmap-value' => 64,
      'list-max-ziplist-entries' => 512,
      'list-max-ziplist-value' => 64,
      'set-max-intset-entries' => 512,
      'activerehashing' => 'yes',

      # os specific settings
      'dir' => '/var/lib/redis',
      'pidfile' => '/var/run/redis.pid',
      'logfile' => '/var/log/redis/redis-server.log',
      'vm-swap-file' => '/var/lib/redis/redis.swap'
    }
  end
  
  def generate_redis_conf
    @config.boolean_to_string!
    @config = default_config.merge @config
    
    redis_conf = ''
    @config.each do |key, value|
      if value.is_a? Array
        value.each { |v| redis_conf << "#{key} #{v}\n" }
      else
        redis_conf << "#{key} #{value}\n"
      end
    end
    
    redis_conf
  end
end
