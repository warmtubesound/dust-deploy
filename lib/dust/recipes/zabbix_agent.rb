class ZabbixAgent < Recipe
  desc 'zabbix_agent:deploy', 'installs and configures zabbix agent'
  def deploy 
    return unless install_zabbix

    @node.deploy_file "#{@template_path}/zabbix_agentd.conf", '/etc/zabbix/zabbix_agentd.conf', :binding => binding
    
    # set daemon name, according zu distribution
    daemon = @node.uses_emerge? ? 'zabbix-agentd' : 'zabbix-agent'
    
    # restart using new configuration
    @node.autostart_service daemon
    @node.restart_service daemon if options.restart?
  end

  private
  # installs zabbix and its dependencies
  def install_zabbix

    if @node.uses_apt?
      # debsecan is needed for zabbix checks (security updates)      
      return false unless @node.install_package 'zabbix-agent'
      return false unless @node.install_package 'debsecan'

    elsif @node.uses_emerge?
      # glsa-check (part of gentoolkit) is needed for zabbix checks (security updates)      
      return false unless @node.install_package 'zabbix', :env => 'USE=agent'
      return false unless @node.install_package 'gentoolkit'

    elsif @node.uses_rpm?
      return false unless @node.install_package 'zabbix-agent'

    else
      ::Dust.print_msg 'os not supported'
      ::Dust.print_failed
      return false
    end

    true
  end

  
  # below this line is unfinished code, not in use yet
  
  # TODO (not yet finished)
  desc 'zabbix_agent:postgres', 'configure postgres database for zabbix monitoring'
  def postgres
    next unless @node.uses_emerge? :quiet=>false
    next unless @node.package_installed?('postgresql-@node')

    ::Dust.print_msg 'add zabbix system user to postgres group'
    ::Dust.print_result( @node.exec('usermod -a -G postgres zabbix')[:exit_code] )

    ::Dust.print_msg 'checking if zabbix user exists in postgres'
    ret = ::Dust.print_result( @node.exec('psql -U postgres -c ' +
                                       '  "SELECT usename FROM pg_user WHERE usename = \'zabbix\'"' +
                                       '  postgres |grep -q zabbix')[:exit_code] )

    # if user was not found, create him
    unless ret
      ::Dust.print_msg 'create zabbix user in postgres', :indent => 2
      ::Dust.print_result( @node.exec('createuser -U postgres zabbix -RSD')[:exit_code] )
    end

    # TODO: only GRANT is this is a master
    ::Dust.print_msg 'GRANT zabbix user access to postgres database'
    ::Dust.print_result( @node.exec('psql -U postgres -c "GRANT SELECT ON pg_stat_database TO zabbix" postgres')[:exit_code] )

    # reload postgresql
    @node.reload_service('postgresql-9.0')

    @node.disconnect
    puts
  end
end
