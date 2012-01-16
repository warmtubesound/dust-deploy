class Mysql < Recipe
  desc 'mysql:deploy', 'installs and configures mysql database'
  def deploy
    return unless @node.uses_apt? :quiet=>false
    @node.install_package 'mysql-server'

    ::Dust.print_msg "configuring mysql\n"

    # defaults
    @config['bind_address'] ||= '127.0.0.1'
    @config['port'] ||= 3306

    ::Dust.print_ok "listen on #{@config['bind_address']}:#{@config['port']}", :indent => 2

    @config['innodb_file_per_table'] ||= 1
    @config['innodb_thread_concurrency'] ||= 0
    @config['innodb_flush_log_at_trx_commit'] ||= 1

    # allocate 70% of the available ram to mysql
    # but leave max 1gb to system
    unless @config['innodb_buffer_pool_size']
      ::Dust.print_msg 'autoconfiguring innodb buffer size', :indent => 2
      @node.collect_facts :quiet => true

      # get system memory (in kb)
      system_mem = ::Dust.convert_size @node['memorysize']

      # allocate 70% of the available ram to mysql
      buffer_pool = (system_mem * 0.70).to_i / 1024

      @config['innodb_buffer_pool_size'] = "#{buffer_pool}M"
      ::Dust.print_ok
    end

    ::Dust.print_ok "setting innodb buffer pool to '#{@config['innodb_buffer_pool_size']}'", :indent => 2

    @node.deploy_file "#{@template_path}/my.cnf", '/etc/mysql/my.cnf', :binding => binding
    @node.chmod '644', '/etc/mysql/my.cnf'

    @node.restart_service 'mysql-server' if options.restart?
    @node.reload_service 'mysql-server' if options.reload?
  end
end

