class Postgres < Recipe
  desc 'postgres:deploy', 'installs and configures postgresql database'
  def deploy
    return ::Dust.print_failed 'no version specified' unless @config['version']

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
      return 'os not supported'
    end


    @node.deploy_file "#{@template_path}/postgresql.conf", "#{@config['conf-dir']}/postgresql.conf", :binding => binding
    @node.deploy_file "#{@template_path}/pg_hba.conf", "#{@config['conf-dir']}/pg_hba.conf", :binding => binding
    @node.deploy_file "#{@template_path}/pg_ident.conf", "#{@config['conf-dir']}/pg_ident.conf", :binding => binding

    @node.chmod '644', "#{@config['conf-dir']}/postgresql.conf"
    @node.chmod '644', "#{@config['conf-dir']}/pg_hba.conf"
    @node.chmod '644', "#{@config['conf-dir']}/pg_ident.conf"

    # deploy pacemaker script
    if @node.package_installed? 'pacemaker'
      @node.deploy_file "#{@template_path}/pacemaker.sh", "#{@config['conf-dir']}/pacemaker.sh", :binding => binding
      @node.chmod '755', "#{@config['conf-dir']}/pacemaker.sh"
    end

    # copy recovery.conf to either recovery.conf or recovery.done
    # depending on which file already exists.
    if @node.file_exists? "#{@config['data-dir']}/recovery.conf", :quiet => true
      @node.deploy_file "#{@template_path}/recovery.conf", "#{@config['data-dir']}/recovery.conf", :binding => binding
    else
      @node.deploy_file "#{@template_path}/recovery.conf", "#{@config['data-dir']}/recovery.done", :binding => binding
    end

    # deploy certificates to data-dir
    @node.deploy_file "#{@template_path}/server.crt", "#{@config['data-dir']}/server.crt", :binding => binding
    @node.deploy_file "#{@template_path}/server.key", "#{@config['data-dir']}/server.key", :binding => binding

    @node.chown @config['dbuser'], @config['data-dir'] if @config['dbuser']
    @node.chmod 'u+Xrw,g-rwx,o-rwx', @config['data-dir']

    # create archive dir
    @node.mkdir @config['archive-dir']
    @node.chown @config['dbuser'], @config['archive-dir'] if @config['dbuser']
    @node.chmod 'u+Xrw,g-rwx,o-rwx', @config['archive-dir']


    # increase shm memory
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

    # reload/restart postgres if command line option is given
    @node.restart_service @config['service-name'] if options.restart?
    @node.reload_service @config['service-name'] if options.reload?
  end

end

