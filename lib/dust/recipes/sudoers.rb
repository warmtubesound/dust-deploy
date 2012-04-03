class Sudoers < Recipe
  desc 'sudoers:deploy', 'installs email aliases'
  def deploy 
    return unless @node.install_package 'sudo'
    
    remove_rules
    
    @config.each do |name, rule|
      ::Dust.print_msg "deploying sudo rules '#{name}'\n"
      
      # rulename: 'myrule' 
      if rule.is_a? String
        file = "#{rule}\n"
        
      # rulename: { user: [ user1, user2 ], command: [ cmd1, cmd2 ] }
      else
        unless rule['user'] and rule['command']
          ::Dust.print_failed 'user or command missing', :indent => 2
          next
        end
        
        file = ''        
        rule['user'].each do |u|
          rule['command'].each { |c| file << "#{u} #{c}\n" }
        end
      end
      
      deploy_rule name, file
    end
    
  end
  

  private
  
  def remove_rules
    @node.rm '/etc/sudoers.d/*'
  end
  
  def deploy_rule name, file
    @node.write "/etc/sudoers.d/#{name}", file, :indent => 2
    @node.chmod '0440', "/etc/sudoers.d/#{name}", :indent => 2
    @node.chown 'root:root', "/etc/sudoers.d/#{name}", :indent => 2    
  end
end
