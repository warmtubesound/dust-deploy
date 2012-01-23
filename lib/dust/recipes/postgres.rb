class Postgres < Recipe
  desc 'postgres:deploy', 'installs and configures postgresql database'
  def deploy
    return ::Dust.print_failed 'no version specified' unless @config['version']
    return ::Dust.print_failed 'os not supported' unless default_config
    
    deploy_config
    deploy_recovery
    deploy_certificates
    configure_sysctl
    
    deploy_pacemaker_script if @node.package_installed? 'pacemaker'
    configure_for_zabbix if zabbix_installed?
    
    # reload/restart postgres if command line option is given
    @node.restart_service @config['service-name'] if options.restart?
    @node.reload_service @config['service-name'] if options.reload?
  end
    
  
  private
  
  # set default variables and make sure postgres is installed
  def default_config
    if @node.uses_emerge?
      return unless @node.package_installed? 'postgresql-server'
      @config['data-dir'] ||= "/var/lib/postgresql/#{@config['version']}/data"
      @config['conf-dir'] ||= "/etc/postgresql-#{@config['version']}"
      @config['archive-dir'] ||= "/var/lib/postgresql/#{@config['version']}/archive"
      @config['service-name'] ||= "postgresql-#{@config['version']}"

    elsif @node.uses_apt?
      return unless @node.package_installed? "postgresql-#{@config['version']}"
      @config['data-dir'] ||= "/var/lib/postgresql/#{@config['version']}/#{@config['cluster']}"
      @config['conf-dir'] ||= "/etc/postgresql/#{@config['version']}/#{@config['cluster']}"
      @config['archive-dir'] ||= "/var/lib/postgresql/#{@config['version']}/#{@config['cluster']}-archive"
      @config['service-name'] ||= 'postgresql'

    else
      return ::Dust.print_failed 'os not supported yet'
    end
  end

  # deploy standard postgres config
  def deploy_config
    @node.deploy_file "#{@template_path}/postgresql.conf", "#{@config['conf-dir']}/postgresql.conf", :binding => binding
    @node.deploy_file "#{@template_path}/pg_hba.conf", "#{@config['conf-dir']}/pg_hba.conf", :binding => binding
    @node.deploy_file "#{@template_path}/pg_ident.conf", "#{@config['conf-dir']}/pg_ident.conf", :binding => binding

    @node.chmod '644', "#{@config['conf-dir']}/postgresql.conf"
    @node.chmod '644', "#{@config['conf-dir']}/pg_hba.conf"
    @node.chmod '644', "#{@config['conf-dir']}/pg_ident.conf"
  end
  
  # copy recovery.conf to either recovery.conf or recovery.done
  # depending on which file already exists.
  def deploy_recovery
    if @node.file_exists? "#{@config['data-dir']}/recovery.conf", :quiet => true
      @node.deploy_file "#{@template_path}/recovery.conf", "#{@config['data-dir']}/recovery.conf", :binding => binding
    else
      @node.deploy_file "#{@template_path}/recovery.conf", "#{@config['data-dir']}/recovery.done", :binding => binding
    end
  end
    
  # deploy certificates to data-dir  
  def deploy_certificates
    @node.deploy_file "#{@template_path}/server.crt", "#{@config['data-dir']}/server.crt", :binding => binding
    @node.deploy_file "#{@template_path}/server.key", "#{@config['data-dir']}/server.key", :binding => binding

    @node.chown @config['dbuser'], @config['data-dir'] if @config['dbuser']
    @node.chmod 'u+Xrw,g-rwx,o-rwx', @config['data-dir']

    # create archive dir
    @node.mkdir @config['archive-dir']
    @node.chown @config['dbuser'], @config['archive-dir'] if @config['dbuser']
    @node.chmod 'u+Xrw,g-rwx,o-rwx', @config['archive-dir']
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
    end
  end

  def deploy_pacemaker_script
    @node.deploy_file "#{@template_path}/pacemaker.sh", "#{@config['conf-dir']}/pacemaker.sh", :binding => binding
    @node.chmod '755', "#{@config['conf-dir']}/pacemaker.sh"
  end
  
  # below this line is unfinished code, not in use yet
  def zabbix_installed?
    if @node.uses_emerge?
      return @node.package_installed? 'zabbix', :quiet => true
    else
      return @node.package_installed? 'zabbix-agent', :quiet => true
    end
  end
  
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
    if @node.file_exists? "#{@config['data-dir']}/recovery.done", :quiet => true
      ::Dust.print_ok 'yes', :indent => 0
      return true
    else
      ::Dust.print_ok 'no', :indent => 0
      return false
    end
  end
end

