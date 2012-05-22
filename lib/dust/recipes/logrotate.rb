class Logrotate < Recipe
  desc 'logrotate:deploy', 'installs logrotate rules'
  def deploy 
    return unless @node.install_package 'logrotate'
    
    @config.each do |name, rule|
      @node.messages.add("deploying logrotate entry for '#{name}'\n")

      unless rule['path']
        @node.messages.add('path not specified', :indent => 2).failed
        next
      end
      
      file = "#{rule['path']} {\n"
      
      rule['args'] ||= default_args
      rule['args'].each { |arg| file << "    #{arg}\n" }

      rule['scripts'] ||= {}
      rule['scripts'].each do |script, commands|
        file << "    #{script}\n"
        commands.each { |cmd| file << "        #{cmd}\n" }
      end
        
      file << "}\n"
      deploy_rule name, file
    end
    
  end

  desc 'logrotate:status', 'displays filenames of installed logrotate rules'
  def status
    @node.messages.add.print_output(@node.exec('ls /etc/logrotate.d/*'))
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
    @node.chown 'root:root', "/etc/logrotate.d/#{name}", :indent => 2    
  end

end
