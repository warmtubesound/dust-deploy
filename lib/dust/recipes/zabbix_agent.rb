class ZabbixAgent < Recipe
  desc 'zabbix_agent:deploy', 'installs and configures zabbix agent'
  def deploy 
    return unless install_zabbix
    
    # set daemon name, according zu distribution
    daemon = @node.uses_emerge? ? 'zabbix-agentd' : 'zabbix-agent'
    
    @node.write '/etc/zabbix/zabbix_agentd.conf', generate_zabbix_agentd_conf
    
    # restart using new configuration
    @node.autostart_service daemon
    @node.restart_service daemon if options.restart?
  end

  desc 'zabbix_agent:status', 'displays status of the zabbix agent'
  def status
    daemon = @node.uses_emerge? ? 'zabbix-agentd' : 'zabbix-agent'
    return unless @node.package_installed? daemon
    @node.print_service_status  daemon
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
  
  # generate zabbix_agentd.conf
  def generate_zabbix_agentd_conf
    @config = default_config.merge @config 

    @config['UserParameter'] = Array @config['UserParameter']

    # system updates
    @config['UserParameter'] |= enable_apt if @node.uses_apt?
    @config['UserParameter'] |= enable_rpm if @node.uses_rpm?
    @config['UserParameter'] |= enable_emerge if @node.uses_emerge?
    
    # additional monitoring (raid status and postgresql)
    @config['UserParameter'] |= enable_postgres if @node.package_installed? [ 'postgresql-server', 'postgresql' ], :quiet => true
    @config['UserParameter'] |= enable_arcconf if @node.package_installed? 'arcconf', :quiet => true
    
    zabbix_agentd_conf = ''
    
    # add normal configuration variables
    @config.each do |key, value|
      next if key == 'UserParameter'
      zabbix_agentd_conf << "#{key}=#{value}\n"
    end    
    
    # add user parameters
    @config['UserParameter'].each do |user_parameter|
      zabbix_agentd_conf << "UserParameter=#{user_parameter}\n"
    end
    
    zabbix_agentd_conf
  end
  
  # default zabbix_agentd.conf configuration options
  def default_config
    defaults = { 
      'StartAgents' => 5,
      'DebugLevel' => 3,
      'Timeout' => 30,
      'Hostname' => @node['fqdn'],
      'UserParameter' => []
    }
      
    if @node.uses_apt?
      defaults['PidFile'] ||= '/var/run/zabbix-agent/zabbix_agentd.pid'
      defaults['LogFile'] ||= '/var/log/zabbix-agent/zabbix_agentd.log'
    elsif @node.uses_emerge? or @node.uses_rpm?
      defaults['PidFile'] ||= '/var/run/zabbix/zabbix_agentd.pid'
      defaults['LogFile'] ||= '/var/log/zabbix/zabbix_agentd.log'
    end
    
    defaults
  end
  
  # monitor postgres database
  def enable_postgres
    [ 'psql.version,psql --version|head -n1',
      'psql.server_processes,psql -U zabbix -t -c "select sum(numbackends) from pg_stat_database" postgres',
      'psql.db_connections,psql -U zabbix -t -c "select count(*) from pg_stat_activity" postgres',
      'psql.db_fetched,psql -U zabbix -t -c "select sum(tup_fetched) from pg_stat_database" postgres',
      'psql.db_deleted,psql -U zabbix -t -c "select sum(tup_deleted) from pg_stat_database" postgres',
      'psql.db_inserted,psql -U zabbix -t -c "select sum(tup_inserted) from pg_stat_database" postgres',
      'psql.db_returned,psql -U zabbix -t -c "select sum(tup_returned) from pg_stat_database" postgres',
      'psql.db_updated,psql -U zabbix -t -c "select sum(tup_updated) from pg_stat_database" postgres',
      'psql.tx_commited,psql -U zabbix -t -c "select sum(xact_commit) from pg_stat_database" postgres',
      'psql.tx_rolledback,psql -U zabbix -t -c "select sum(xact_rollback) from pg_stat_database" postgres',
      'psql.blks_hit,psql -U zabbix -t -c "select sum(blks_hit) from pg_stat_database" postgres',
      'psql.blks_read,psql -U zabbix -t -c "select sum(blks_read) from pg_stat_database" postgres'
    ]
  end

  # monitor adaptec raid status
  def enable_arcconf
    [ 'raid.smart_warnings,/sbin/arcconf getconfig 1 pd |grep "S.M.A.R.T. warnings" | awk "{SMART += $4} END {print SMART}"',
      'raid.disk_rpm,/sbin/arcconf getconfig 1 pd |grep "Power State" |grep -v "Full rpm" |wc -l',
      'raid.disk_state,/sbin/arcconf getconfig 1 pd |grep "\s\sState" |grep -v "Online" |wc -l' 
    ]
  end
  
  # check for security patches and system updates on emerge systems 
  def enable_apt
    [ 'debian.updates,aptitude search \'~U\' |wc -l',
      'debian.security,debsecan --suite squeeze --only-fixed --format packages |wc -l'
    ]
  end

  # check for security patches and system updates on emerge systems  
  def enable_rpm
    [ 'centos.updates,yum check-update -q |wc -l' ]
  end
  
  # check for security patches and system updates on emerge systems
  def enable_emerge
    [ 'gentoo.security,glsa-check -t all 2>/dev/null | wc -l',
      'gentoo.updates,emerge -uNDp @world | grep ebuild|wc -l',
      'gentoo.portage,emerge --info| grep "Timestamp of tree" | sed -e s/\'Timestamp of tree\':// -e \'s/\n//\' | xargs -I {} date --date={} +%s |xargs -I {} expr $(date +%s) - {}',
      'gentoo.config,find /etc/ -name "._cfg*" 2>/dev/null|wc -l'
    ]
  end
end
