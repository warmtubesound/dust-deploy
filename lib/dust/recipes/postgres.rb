class Postgres < Recipe
  desc 'postgres:deploy', 'installs and configures postgresql database'
  def deploy
    return ::Dust.print_failed 'no version specified' unless @config['version']
    return unless install_postgres
    
    # default cluster on debian-like systems is 'main'
    @config['cluster'] ||= 'main' if @node.uses_apt?
    
    set_default_directories
    deploy_config
    deploy_recovery
    deploy_certificates if @config['server.crt'] and @config['server.key']
    create_archive
    set_permissions
    configure_sysctl
    
    deploy_pacemaker_script if @node.package_installed? 'pacemaker', :quiet => true
    configure_for_zabbix if zabbix_installed?
    
    # reload/restart postgres if command line option is given
    @node.restart_service @config['service_name'] if options.restart?
    @node.reload_service @config['service_name'] if options.reload?
  end
    
  
  private
  
  def install_postgres
    if @node.uses_apt?      
      package = "postgresql-#{@config['version']}"
    elsif @node.uses_emerge?    
      package = 'postgresql-server'
    else
      return ::Dust.print_failed 'os not supported'
    end
    
    @node.install_package package

    # also install the postgresql meta package
    @node.install_package 'postgresql' if @node.uses_apt?
  end

  # set conf-dir, archive-dir and data-dir as well as service-name
  # according to config file, or use standard values of distribution
  def set_default_directories
    if @node.uses_emerge?
      @config['conf_directory'] ||= "/etc/postgresql-#{@config['version']}"
      @config['archive_directory'] ||= "/var/lib/postgresql/#{@config['version']}/archive"
      @config['service_name'] ||= "postgresql-#{@config['version']}"
      @config['postgresql.conf']['data_directory'] ||= "/var/lib/postgresql/#{@config['version']}/data"    
      
    elsif @node.uses_apt?
      @config['postgresql.conf']['data_directory'] ||= "/var/lib/postgresql/#{@config['version']}/#{@config['cluster']}"
      @config['conf_directory'] ||= "/etc/postgresql/#{@config['version']}/#{@config['cluster']}"
      @config['archive_directory'] ||= "/var/lib/postgresql/#{@config['version']}/#{@config['cluster']}-archive"
      @config['service_name'] ||= 'postgresql'
    end
    
    @config['postgresql.conf']['hba_file'] ||= "#{@config['conf_directory']}/pg_hba.conf"
    @config['postgresql.conf']['ident_file'] ||= "#{@config['conf_directory']}/pg_ident.conf"    
  end
  
  # deploy postgresql.conf, pg_hba.conf and pg_ident.conf
  def deploy_config
    @node.write "#{@config['conf_directory']}/postgresql.conf", generate_postgresql_conf
    @node.write "#{@config['conf_directory']}/pg_hba.conf", generate_pg_hba_conf
    @node.write "#{@config['conf_directory']}/pg_ident.conf", generate_pg_ident_conf
    @node.chmod '644', "#{@config['conf_directory']}/postgresql.conf"
    @node.chmod '644', "#{@config['conf_directory']}/pg_hba.conf"
    @node.chmod '644', "#{@config['conf_directory']}/pg_ident.conf"
  end
  
  # copy recovery.conf to either recovery.conf or recovery.done
  # depending on which file already exists.
  def deploy_recovery
    if @node.file_exists? "#{@config['postgresql.conf']['data_directory']}/recovery.conf", :quiet => true
      @node.write "#{@config['postgresql.conf']['data_directory']}/recovery.conf", generate_recovery_conf
    else
      @node.write "#{@config['postgresql.conf']['data_directory']}/recovery.done", generate_recovery_conf
    end
  end
    
  # deploy certificates to data-dir  
  def deploy_certificates
    @node.deploy_file "#{@template_path}/#{@config['server.crt']}", "#{@config['postgresql.conf']['data_directory']}/server.crt", :binding => binding
    @node.deploy_file "#{@template_path}/#{@config['server.key']}", "#{@config['postgresql.conf']['data_directory']}/server.key", :binding => binding
  end

  # increase shm memory  
  def configure_sysctl
    if @node.uses_apt?
      ::Dust.print_msg "setting postgres sysctl keys\n"
      @node.collect_facts :quiet => true

      # use half of system memory for shmmax
      shmmax = ::Dust.convert_size(@node['memorysize']) * 1024 / 2
      shmall = shmmax / 4096 # shmmax/pagesize (pagesize = 4096)

      ::Dust.print_msg "setting shmmax to: #{shmmax}", :indent => 2
      ::Dust.print_result @node.exec("sysctl -w kernel.shmmax=#{shmmax}")[:exit_code]
      ::Dust.print_msg "setting shmall to: #{shmall}", :indent => 2
      ::Dust.print_result @node.exec("sysctl -w kernel.shmall=#{shmall}")[:exit_code]
      ::Dust.print_msg 'setting overcommit memory to 2', :indent => 2
      ::Dust.print_result @node.exec('sysctl -w vm.overcommit_memory=2')[:exit_code]
      ::Dust.print_msg 'setting swappiness to 0', :indent => 2
      ::Dust.print_result @node.exec('sysctl -w vm.swappiness=0')[:exit_code]

      file = ''
      file += "kernel.shmmax=#{shmmax}\n"
      file += "kernel.shmall=#{shmall}\n"
      file += "vm.overcommit_memory=2\n" # don't allocate memory that's not there
      file += "vm.swappiness=0\n" # rather shrink cache then use swap as filesystem cache

      @node.write "/etc/sysctl.d/30-postgresql-shm.conf", file
      
    else
      ::Dust.print_warning 'sysctl configuration not supported for your os'
    end
  end
  
  # default settings for postgresql.conf
  def default_postgres_conf
    { 'max_connections' => 100,
      'datestyle' => 'iso, mdy',
      'lc_messages' => 'en_US.UTF-8',
      'lc_monetary' => 'en_US.UTF-8',
      'lc_numeric' => 'en_US.UTF-8',
      'lc_time' => 'en_US.UTF-8',
      'default_text_search_config' => 'pg_catalog.english' }
  end
  
  def generate_postgresql_conf
    @config['postgresql.conf'] = default_postgres_conf.merge @config['postgresql.conf']
    
    calculate_values
    
    postgresql_conf = ''
    @config['postgresql.conf'].each do |key, value|
      value = "'#{value}'" if value.is_a? String # enclose strings in ''
      postgresql_conf.concat "#{key} = #{value}\n"
    end
    
    postgresql_conf
  end
  
  def generate_recovery_conf
    @config['recovery.conf'] ||= []
    
    recovery_conf = ''
    @config['recovery.conf'].each do |key, value|
      value = "'#{value}'" if value.is_a? String # enclose strings in ''
      recovery_conf.concat "#{key} = #{value}\n"
    end
    
    recovery_conf
  end
  
  def generate_pg_hba_conf
    @config['pg_hba.conf'] ||= [ 'local   all         postgres                trust' ]
    @config['pg_hba.conf'].join "\n"
  end

  def generate_pg_ident_conf
    @config['pg_ident.conf'] ||= []
    @config['pg_ident.conf'].join "\n"
  end
  
  # try to find good values (but don't overwrite if set in config file) for
  # shared_buffers, work_mem and maintenance_work_mem, effective_cache_size and wal_buffers
  def calculate_values
    @node.collect_facts :quiet => true
    system_mem = ::Dust.convert_size(@node['memorysize']).to_f
    
    ::Dust.print_msg "calculating recommended settings for #{kb2mb system_mem} ram\n"
  
    # every connection uses up to work_mem memory, so make sure that even if
    # max_connections is reached, there's still a bit left.
    # total available memory / (2 * max_connections)
    @config['postgresql.conf']['work_mem'] ||= kb2mb(system_mem * 0.9 / @config['postgresql.conf']['max_connections'])
    ::Dust.print_ok "work_mem: #{@config['postgresql.conf']['work_mem']}", :indent => 2
    
    # shared_buffers should be 0.2 - 0.3 of system ram
    # unless ram is lower than 1gb, then less (32mb maybe)    
    @config['postgresql.conf']['shared_buffers'] ||= kb2mb(system_mem * 0.25)
    ::Dust.print_ok "shared_buffers: #{@config['postgresql.conf']['shared_buffers']}", :indent => 2
    
    # maintenance_work_mem, should be a lot higher than work_mem 
    # recommended value: 50mb for each 1gb of system ram
    @config['postgresql.conf']['maintenance_work_mem'] ||= kb2mb(system_mem / 1024 * 50)
    ::Dust.print_ok "maintenance_work_mem: #{@config['postgresql.conf']['maintenance_work_mem']}", :indent => 2
    
    # effective_cache_size between 0.6 and 0.8 of system ram
    @config['postgresql.conf']['effective_cache_size'] ||= kb2mb(system_mem * 0.75)
    ::Dust.print_ok "effective_cache_size: #{@config['postgresql.conf']['effective_cache_size']}", :indent => 2
    
    # wal_buffers should be between 2-16mb
    @config['postgresql.conf']['wal_buffers'] ||= '12MB'
    ::Dust.print_ok "wal_buffers: #{@config['postgresql.conf']['wal_buffers']}", :indent => 2    
  end
  
  # converts plain kb value to "1234MB"
  def kb2mb value
    "#{(value / 1024).to_i}MB"
  end
  
  # give the configured dbuser the data_directory
  def set_permissions
    @node.chown @config['dbuser'], @config['postgresql.conf']['data_directory'] if @config['dbuser']
    @node.chmod 'u+Xrw,g-rwx,o-rwx', @config['postgresql.conf']['data_directory']
  end
  
  # create archive dir
  def create_archive
    @node.mkdir @config['archive_directory']
    @node.chown @config['dbuser'], @config['archive_directory'] if @config['dbuser']
    @node.chmod 'u+Xrw,g-rwx,o-rwx', @config['archive_directory']
  end
  
  # deploy the pacemaker script
  def deploy_pacemaker_script
    @node.deploy_file "#{@template_path}/pacemaker.sh", "#{@config['conf_directory']}/pacemaker.sh", :binding => binding
    @node.chmod '755', "#{@config['conf_directory']}/pacemaker.sh"
  end  
  
  # check if zabbix is installed
  def zabbix_installed?
    if @node.uses_emerge?
      return @node.package_installed? 'zabbix', :quiet => true
    else
      return @node.package_installed? 'zabbix-agent', :quiet => true
    end
  end
  
  # configures postgres for zabbix monitoring:
  # adds zabbix user to postgres group
  # creates zabbix user in postgres and grant access to postgres database
  def configure_for_zabbix
    ::Dust.print_msg "configuring postgres for zabbix monitoring\n"
    ::Dust.print_msg 'adding zabbix user to postgres group', :indent => 2
    ::Dust.print_result @node.exec('usermod -a -G postgres zabbix')[:exit_code]
    
    if is_master? :indent => 2
      ::Dust.print_msg 'checking if zabbix user exists in postgres', :indent => 3
      ret = ::Dust.print_result @node.exec('psql -U postgres -c ' +
                                           '  "SELECT usename FROM pg_user WHERE usename = \'zabbix\'"' +
                                           '  postgres |grep -q zabbix')[:exit_code]
      
      # if user was not found, create him
      unless ret
        ::Dust.print_msg 'create zabbix user in postgres', :indent => 4
        ::Dust.print_result @node.exec('createuser -U postgres zabbix -RSD')[:exit_code]
      end
      
      ::Dust.print_msg 'GRANT zabbix user access to postgres database', :indent => 3
      ::Dust.print_result( @node.exec('psql -U postgres -c "GRANT SELECT ON pg_stat_database TO zabbix" postgres')[:exit_code] )
    end
  end  
  
  # checks if this server is a postgres master
  def is_master? options = {}
    ::Dust.print_msg 'checking if this host is the postgres master: ', options
    if @node.file_exists? "#{@config['postgresql.conf']['data_directory']}/recovery.done", :quiet => true
      ::Dust.print_ok 'yes', :indent => 0
      return true
      else
      ::Dust.print_ok 'no', :indent => 0
      return false
    end
  end  
end
