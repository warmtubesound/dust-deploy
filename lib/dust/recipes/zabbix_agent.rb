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
end
