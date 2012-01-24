class Mysql < Recipe
  desc 'mysql:deploy', 'installs and configures mysql database'
  def deploy
    return unless @node.uses_apt? :quiet=>false
    @node.install_package 'mysql-server'

    @config = default_config.deep_merge @config
    
    ::Dust.print_msg "configuring mysql\n"
    ::Dust.print_ok "listen on #{@config['mysqld']['bind-address']}:#{@config['mysqld']['port']}", :indent => 2

    @config['mysqld']['innodb_buffer_pool_size'] = get_innodb_buffer_pool_size
    ::Dust.print_ok "set innodb buffer pool to '#{@config['mysqld']['innodb_buffer_pool_size']}'", :indent => 2

    @node.write '/etc/mysql/my.cnf', generate_my_cnf
    @node.chmod '644', '/etc/mysql/my.cnf'

    @node.restart_service 'mysql' if options.restart?
    @node.reload_service 'mysql' if options.reload?
  end
  
  
  private
  
  def default_config
    { 'client' => {
        'port' => 3306,
        'socket' => '/var/run/mysqld/mysqld.sock'
      },
      'mysqld_safe' => {
        'socket' => '/var/run/mysqld/mysqld.sock',
        'nice' => 0
      },
      'mysqld' => {
        'bind-address' => '127.0.0.1',
        'port' => 3306,
        'user' => 'mysql',
        'pid-file' => '/var/run/mysqld/mysqld.pid',
        'socket' => '/var/run/mysqld/mysqld.sock',
        'language' => '/usr/share/mysql/english',        
        'basedir' => '/usr',
        'datadir' => '/var/lib/mysql',
        'tmpdir' => '/tmp',
        'skip-external-locking' => true,
        'key_buffer' => '16M',
        'max_allowed_packet' => '16M',
        'thread_stack' => '192K',
        'thread_cache_size' => 8,
        'myisam-recover' => 'BACKUP',
        'query_cache_limit' => '1M',
        'query_cache_size' => '16M',
        'expire_logs_days' => 10,
        'max_binlog_size' => '100M',
        'innodb_file_per_table' => 1,
        'innodb_thread_concurrency' => 0,
        'innodb_flush_log_at_trx_commit' => 1
      },
      'mysqldump' => {
        'quick' => true,
        'quote-names' => true,
        'max_allowed_packet' => '16M'
      },
      'mysql' => {},
      'isamchk' => {
        'key_buffer' => '16M',
      }
    }
  end
  
  def get_innodb_buffer_pool_size
    # allocate 70% of the available ram to mysql
    # but leave max 1gb to system
    unless @config['mysqld']['innodb_buffer_pool_size']
      ::Dust.print_msg 'autoconfiguring innodb buffer size', :indent => 2
      @node.collect_facts :quiet => true
  
      # get system memory (in kb)
      system_mem = ::Dust.convert_size @node['memorysize']
  
      # allocate 70% of the available ram to mysql
      buffer_pool = (system_mem * 0.70).to_i / 1024
     
      ::Dust.print_ok
      "#{buffer_pool}M"
    end
  end
  
  def generate_my_cnf
    my_cnf = ''
    @config.each do |category, config|
      my_cnf.concat "[#{category}]\n"
      config.each { |key, value| my_cnf.concat "#{key} = #{value}\n" }
      my_cnf.concat "\n"
    end
    
    # add includedir
    my_cnf.concat "!includedir /etc/mysql/conf.d/\n"
    my_cnf
  end
end

