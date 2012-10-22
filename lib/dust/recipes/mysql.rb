class Mysql < Recipe
  desc 'mysql:deploy', 'installs and configures mysql database'
  def deploy
    # apt/yum both use mysql-server
    @node.install_package 'mysql-server'

    service = @node.uses_rpm? ? 'mysqld' : 'mysql'
    config = @node.uses_rpm? ? '/etc/my.cnf' : '/etc/mysql/my.cnf'

    @config = default_config.deep_merge @config

    @node.messages.add("configuring mysql\n")
    @node.messages.add("listen on #{@config['mysqld']['bind-address']}:#{@config['mysqld']['port']}", :indent => 2).ok

    @config['mysqld']['innodb_buffer_pool_size'] ||= get_innodb_buffer_pool_size
    @node.messages.add("set innodb buffer pool to '#{@config['mysqld']['innodb_buffer_pool_size']}'", :indent => 2).ok

    @node.write(config, generate_my_cnf)

    @node.restart_service(service) if options.restart?
    @node.reload_service(service) if options.reload?
  end

  desc 'mysql:status', 'displays status of the mysql daemon'
  def status
    return unless @node.package_installed? 'mysql-server'
    @node.print_service_status('mysql')
  end


  private

  def default_config
    my_cnf = {}

    # overall defaults
    my_cnf['mysqld'] = {
      'bind-address' => '127.0.0.1',
      'port' => 3306,
      'user' => 'mysql',
      'symbolic-links' => 0,
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
      'innodb_flush_log_at_trx_commit' => 1,
      'innodb_additional_mem_pool_size' => '16M',
      'innodb_log_buffer_size' => '4M'
    }

    my_cnf['mysqldump'] = {
      'quick' => true,
      'quote-names' => true,
      'max_allowed_packet' => '16M'
    }

    my_cnf['mysql'] = {}

    my_cnf['isamchk'] = {
      'key_buffer' => '16M'
    }

    # debian specific
    if @node.uses_apt?
      my_cnf['client'] = {
        'port' => 3306,
        'socket' => '/var/run/mysqld/mysqld.sock'
      }

      my_cnf['mysqld_safe'] = {
        'socket' => '/var/run/mysqld/mysqld.sock',
        'nice' => 0
      }

      my_cnf['mysqld']['pid-file'] = '/var/run/mysqld/mysqld.pid'
      my_cnf['mysqld']['socket'] = '/var/run/mysqld/mysqld.sock'
      my_cnf['mysqld']['language'] = '/usr/share/mysql/english'
      my_cnf['mysqld']['basedir'] = '/usr'
      my_cnf['mysqld']['datadir'] = '/var/lib/mysql'
      my_cnf['mysqld']['tmpdir'] = '/tmp'
    end

    # centos specific
    if @node.uses_rpm?
      my_cnf['mysqld_safe'] =  {
        'log-error' => '/var/log/mysqld.log',
        'pid-file' => '/var/run/mysqld/mysqld.pid'
      }

      my_cnf['mysqld']['datadir'] = '/var/lib/mysql'
      my_cnf['mysqld']['socket'] = '/var/lib/mysql/mysql.sock'
    end

    my_cnf
  end

  def get_innodb_buffer_pool_size
    # allocate 70% of the available ram to mysql
    # but leave max 1gb to system
    unless @config['mysqld']['innodb_buffer_pool_size']
      msg = @node.messages.add('autoconfiguring innodb buffer size', :indent => 2)
      @node.collect_facts :quiet => true

      # get system memory (in kb)
      system_mem = ::Dust.convert_size @node['memorysize']

      # allocate 80% of the available ram to mysql
      buffer_pool = (system_mem * 0.7).to_i

      msg.ok
      "#{buffer_pool / 1024}M"
    end
  end

  def generate_my_cnf
    my_cnf = ''
    @config.each do |category, config|
      my_cnf << "[#{category}]\n"
      config.each { |key, value| my_cnf << "#{key} = #{value}\n" }
      my_cnf << "\n"
    end

    # add includedir on debian/ubuntu
    my_cnf << "!includedir /etc/mysql/conf.d/\n" if @node.uses_apt?
    my_cnf
  end
end
