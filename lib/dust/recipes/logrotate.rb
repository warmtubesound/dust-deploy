class Logrotate < Recipe
  desc 'logrotate:deploy', 'installs logrotate rules'
  def deploy 
    return unless @node.install_package 'logrotate'
    
    @config.each do |name, rule|
      ::Dust.print_msg "deploying logrotate entry for '#{name}'\n"

      unless rule['path']
        ::Dust.print_failed 'path not specified', :indent => 2
        next
      end
      
      file = "#{rule['path']} {\n"
      
      rule['args'] ||= default_args
      rule['args'].each { |arg| file.concat "    #{arg}\n" }

      rule['scripts'] ||= {}
      rule['scripts'].each do |script, commands|
        file.concat "    #{script}\n"
        commands.each { |cmd| file.concat "        #{cmd}\n" }
      end
        
      file.concat "}\n"
      deploy_rule name, file
    end
    
  end

  desc 'logrotate:status', 'displays filenames of installed logrotate rules'
  def status
    ::Dust.print_ret @node.exec('ls /etc/logrotate.d/*')
  end

  private

  def default_args
    [ 'rotate 7', 'daily', 'missingok', 'notifempty', 'copytruncate', 'compress' ]
  end

  def remove_rules
    @node.rm '/etc/logrotate.d/*'
  end
  
  def deploy_rule name, file
    @node.write "/etc/logrotate.d/#{name}", file, :indent => 2
    @node.chmod '0644', "/etc/logrotate.d/#{name}", :indent => 2
    @node.chown 'root:root', "/etc/logrotate.d/#{name}", :indent => 2    
  end

end
