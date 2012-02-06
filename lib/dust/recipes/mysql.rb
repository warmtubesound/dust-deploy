class Mysql < Recipe
  desc 'mysql:deploy', 'installs and configures mysql database'
  def deploy
    return unless @node.uses_apt? :quiet=>false
    @node.install_package 'mysql-server'

    @config = default_config.deep_merge @config
    
    ::Dust.print_msg "configuring mysql\n"
    ::Dust.print_ok "listen on #{@config['mysqld']['bind-address']}:#{@config['mysqld']['port']}", :indent => 2

    @config['mysqld']['innodb_buffer_pool_size'] ||= get_innodb_buffer_pool_size
    ::Dust.print_ok "set innodb buffer pool to '#{@config['mysqld']['innodb_buffer_pool_size']}'", :indent => 2

    @node.write '/etc/mysql/my.cnf', generate_my_cnf
    @node.chmod '644', '/etc/mysql/my.cnf'
        
    configure_sysctl
    
    @node.restart_service 'mysql' if options.restart?
    @node.reload_service 'mysql' if options.reload?
  end
  
  desc 'mysql:status', 'displays status of the mysql daemon'
  def status
    return unless @node.package_installed? 'mysql-server'
    @node.print_service_status 'mysql'
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
        'innodb_flush_log_at_trx_commit' => 1,
        'innodb_additional_mem_pool_size' => '16M',
        'innodb_log_buffer_size' => '4M'
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
  
      # allocate 80% of the available ram to mysql
      buffer_pool = (system_mem * 0.7).to_i
      
      ::Dust.print_ok
      "#{buffer_pool / 1024}M"
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
  
  # increase shm memory  
  def configure_sysctl
    if @node.uses_apt?
      ::Dust.print_msg "setting mysql sysctl keys\n"
      @node.collect_facts :quiet => true
     
      # make sure system allows more than innodb_buffer_pool_size of memory ram to be allocated
      # shmmax = (convert_mysql_size(@config['mysqld']['innodb_buffer_pool_size']) * 1.1).to_i # TODO: 1.1?

      # get pagesize
      pagesize = @node.exec('getconf PAGESIZE')[:stdout].to_i || 4096

      # use half of system memory for shmmax
      shmmax = ::Dust.convert_size(@node['memorysize']) * 1024 / 2
      shmall = shmmax / pagesize
      
      ::Dust.print_msg "setting shmmax to: #{shmmax}", :indent => 2
      ::Dust.print_result @node.exec("sysctl -w kernel.shmmax=#{shmmax}")[:exit_code]
      ::Dust.print_msg "setting shmall to: #{shmall}", :indent => 2
      ::Dust.print_result @node.exec("sysctl -w kernel.shmall=#{shmall}")[:exit_code]
      ::Dust.print_msg 'setting swappiness to 0', :indent => 2
      ::Dust.print_result @node.exec('sysctl -w vm.swappiness=0')[:exit_code]

      file = ''
      file += "kernel.shmmax=#{shmmax}\n"
      file += "kernel.shmall=#{shmall}\n"
      file += "vm.swappiness=0\n" # rather shrink cache then use swap as filesystem cache
      
      @node.write "/etc/sysctl.d/30-mysql-shm.conf", file
      
      else
      ::Dust.print_warning 'sysctl configuration not supported for your os'
    end
  end
  
  def convert_mysql_size s
    case s[-1].chr
      when 'K'
      return (s[0..-2].to_f * 1024).to_i
      when 'M'
      return (s[0..-2].to_f * 1024 * 1024).to_i
      when 'G'
      return (s[0..-2].to_f * 1024 * 1024 * 1024).to_i
      else
      return s.to_i
    end
  end
end

