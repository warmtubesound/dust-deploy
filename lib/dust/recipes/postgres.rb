class Postgres < Recipe
  desc 'postgres:deploy', 'installs and configures postgresql database'
  def deploy
    # version: 9.1
    # package:  postgresql-9.1
    # profile: [ dedicated|standard, zabbix, pacemaker ]
    # service_name: "service name for init scripts"

    return @node.messages.add('please specify version in your config file, e.g. "version: 9.1"').failed unless @config['version']
    return unless install_postgres

    # default cluster on debian-like systems is 'main'
    @config['cluster'] ||= 'main' if @node.uses_apt?


    set_default_directories
    deploy_config
    deploy_recovery
    deploy_certificates if @config['server.crt'] and @config['server.key']
    set_permissions

    # configure pacemaker profile
    if @config['profile'].to_array.include? 'pacemaker'
      deploy_pacemaker_script if @node.package_installed? 'pacemaker'
    end

    # configure zabbix profile
    if @config['profile'].to_array.include? 'zabbix'
      configure_for_zabbix if zabbix_installed?
    end

    # reload/restart postgres if command line option is given
    @node.restart_service @config['service_name'] if options.restart?
    @node.reload_service @config['service_name'] if options.reload?
  end

  desc 'postgres:status', 'displays status of postgres cluster'
  def status
    return unless @node.package_installed? [ 'postgresql-server', "postgresql-#{@config['version']}" ]
    set_default_directories
    @node.print_service_status @config['service_name']
  end


  private

  def install_postgres
    if @config['package']
      package = @config['package']
    elsif @node.uses_apt?
      package = "postgresql-#{@config['version']}"
    elsif @node.uses_emerge?
      package = 'postgresql-server'
    else
      return @node.messages.add('os not supported, please specify "package: <package name>" in your config').failed
    end

    @node.install_package package
  end

  # set conf-dir and data-dir as well as service-name
  # according to config file, or use standard values of distribution
  def set_default_directories
    @config['postgresql.conf'] ||= {} # create empty config, unless present

    if @config['cluster']
      @config['conf_directory'] ||= "/etc/postgresql/#{@config['version']}/#{@config['cluster']}"
      @config['postgresql.conf']['data_directory'] ||= "/var/lib/postgresql/#{@config['version']}/#{@config['cluster']}"
    else
      @config['conf_directory'] ||= "/etc/postgresql-#{@config['version']}"
      @config['postgresql.conf']['data_directory'] ||= "/var/lib/postgresql/#{@config['version']}/data"
    end

    if @node.uses_emerge?
      @config['service_name'] ||= "postgresql-#{@config['version']}"
    else
      # on non-debian and non-emerge systems, print a warning since I'm not sure if service name is correct.
      @node.messages.add('service_name not specified in config, defaulting to "postgresql"').warning unless @node.uses_apt?
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

  # default settings for postgresql.conf
  def default_postgres_conf
    {
      'max_connections' => 100,
      'datestyle' => 'iso, mdy',
      'lc_messages' => 'en_US.UTF-8',
      'lc_monetary' => 'en_US.UTF-8',
      'lc_numeric' => 'en_US.UTF-8',
      'lc_time' => 'en_US.UTF-8',
      'default_text_search_config' => 'pg_catalog.english',
      'log_line_prefix' => '%t [%p] %u@%d '
    }
  end

  def generate_postgresql_conf
    @config['postgresql.conf'] ||= {}
    @config['postgresql.conf'] = default_postgres_conf.merge @config['postgresql.conf']

    # calculate values if dedicated profile is given
    profile_dedicated if @config['profile'].to_array.include? 'dedicated'

    postgresql_conf = ''
    @config['postgresql.conf'].each do |key, value|
      value = "'#{value}'" if value.is_a? String # enclose strings in ''
      postgresql_conf << "#{key} = #{value}\n"
    end

    postgresql_conf
  end

  def generate_recovery_conf
    @config['recovery.conf'] ||= []

    recovery_conf = ''
    @config['recovery.conf'].each do |key, value|
      value = "'#{value}'" if value.is_a? String # enclose strings in ''
      recovery_conf << "#{key} = #{value}\n"
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
  def profile_dedicated
    @node.collect_facts :quiet => true
    system_mem = ::Dust.convert_size(@node['memorysize']).to_f

    msg = @node.messages.add("calculating recommended settings for a dedicated databse server with #{kb2mb system_mem} ram\n")

    # every connection uses up to work_mem memory, so make sure that even if
    # max_connections is reached, there's still a bit left.
    # total available memory / (2 * max_connections)
    @config['postgresql.conf']['work_mem'] ||= kb2mb(system_mem * 0.9 / @config['postgresql.conf']['max_connections'])
    @node.messages.add("work_mem: #{@config['postgresql.conf']['work_mem']}", :indent => 2).ok

    # shared_buffers should be 0.2 - 0.3 of system ram
    # unless ram is lower than 1gb, then less (32mb maybe)
    @config['postgresql.conf']['shared_buffers'] ||= kb2mb(system_mem * 0.25)
    @node.messages.add("shared_buffers: #{@config['postgresql.conf']['shared_buffers']}", :indent => 2).ok

    # maintenance_work_mem, should be a lot higher than work_mem
    # recommended value: 50mb for each 1gb of system ram
    @config['postgresql.conf']['maintenance_work_mem'] ||= kb2mb(system_mem / 1024 * 50)
    @node.messages.add("maintenance_work_mem: #{@config['postgresql.conf']['maintenance_work_mem']}", :indent => 2).ok

    # effective_cache_size between 0.6 and 0.8 of system ram
    @config['postgresql.conf']['effective_cache_size'] ||= kb2mb(system_mem * 0.75)
    @node.messages.add("effective_cache_size: #{@config['postgresql.conf']['effective_cache_size']}", :indent => 2).ok

    # wal_buffers should be between 2-16mb
    @config['postgresql.conf']['wal_buffers'] ||= '12MB'
    @node.messages.add("wal_buffers: #{@config['postgresql.conf']['wal_buffers']}", :indent => 2).ok
  end

  # converts plain kb value to "1234MB"
  def kb2mb value
    "#{(value / 1024).to_i}MB"
  end

  # give the configured dbuser the data_directory
  def set_permissions
    @node.chmod 'u+Xrw,g-rwx,o-rwx', @config['postgresql.conf']['data_directory']
    if @config['dbuser']
      @node.chown("#{@config['dbuser']}:#{@node.get_gid(@config['dbuser'])}", @config['postgresql.conf']['data_directory'])
    end
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
    @node.messages.add("configuring postgres for zabbix monitoring\n")
    msg = @node.messages.add('adding zabbix user to postgres group', :indent => 2)
    msg.parse_result(@node.exec('usermod -a -G postgres zabbix')[:exit_code])

    if is_master? :indent => 2
      msg = @node.messages.add('checking if zabbix user exists in postgres', :indent => 3)
      ret = msg.parse_result(@node.exec('psql -U postgres -c ' +
                                           '  "SELECT usename FROM pg_user WHERE usename = \'zabbix\'"' +
                                           '  postgres |grep -q zabbix')[:exit_code])

      # if user was not found, create him
      unless ret
        msg = @node.messages.add('create zabbix user in postgres', :indent => 4)
        msg.parse_result(@node.exec('createuser -U postgres zabbix -RSD')[:exit_code])
      end

      msg = @node.messages.add('GRANT zabbix user access to postgres database', :indent => 3)
      msg.parse_result(@node.exec('psql -U postgres -c "GRANT SELECT ON pg_stat_database TO zabbix" postgres')[:exit_code])
    end
  end

  # checks if this server is a postgres master
  def is_master? options = {}
    msg = @node.messages.add('checking if this host is the postgres master: ', options)
    if @node.file_exists? "#{@config['postgresql.conf']['data_directory']}/recovery.done", :quiet => true
      msg.ok('yes')
      return true
      else
      msg.ok('no')
      return false
    end
  end
end
