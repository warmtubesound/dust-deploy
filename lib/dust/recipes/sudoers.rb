class Sudoers < Recipe
  desc 'sudoers:deploy', 'installs email aliases'
  def deploy 
    return unless @node.install_package 'sudo'
    
    @config.each do |name, rule|
      @node.messages.add("deploying sudo rules '#{name}'\n")
      
      # rulename: 'myrule' 
      if rule.is_a? String
        file = "#{rule}\n"
        
      # rulename: { user: [ user1, user2 ], command: [ cmd1, cmd2 ] }
      else
        unless rule['user'] and rule['command']
          @node.messages.add('user or command missing', :indent => 2).failed
          next
        end
        
        file = ''        
        rule['user'].each do |u|
          rule['command'].each { |c| file << "#{u} #{c}\n" }
        end
      end
      
      deploy_rule(name, file)
    end
    
    remove_other_rules
  end
  

  private
  
  def remove_other_rules
    msg = @node.messages.add("removing non-dust rules\n")
    ret = @node.exec('ls /etc/sudoers.d/* |cat')
    if ret[:exit_code] != 0
      return @node.messages.add('couldn\'t get installed rule list, skipping deletion of old rules').warning
    end

    # get unmaintained rules
    old_rules = []
    ret[:stdout].each_line do |file|
      file.chomp!
      old_rules << file unless @config.keys.include?(File.basename(file))
    end

    # delete old rules, or display message that none were found
    old_rules.each { |file| @node.rm(file, :indent => 2) }
    @node.messages.add('none found', :indent => 2).ok if old_rules.empty?
  end
  
  def deploy_rule(name, file)
    @node.write("/etc/sudoers.d/#{name}", file, :indent => 2)
    @node.chmod('0440', "/etc/sudoers.d/#{name}", :indent => 2)
    @node.chown('root:root', "/etc/sudoers.d/#{name}", :indent => 2)
  end
end
