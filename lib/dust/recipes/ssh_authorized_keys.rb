require 'yaml'

class SshAuthorizedKeys < Recipe
  desc 'ssh_authorized_keys:deploy', 'configures ssh authorized_keys'
  def deploy

    @config.each do |remote_user, ssh_users|
      ::Dust.print_msg "generating authorized_keys for #{remote_user}\n"
      authorized_keys = generate_authorized_keys ssh_users
      deploy_authorized_keys remote_user, authorized_keys
      puts
    end
  end
  
  
  private

  def generate_authorized_keys ssh_users
    # load users and their ssh keys from yaml file
    users = YAML.load_file "#{@template_path}/users.yaml"    
    authorized_keys = ''
    
    # create the authorized_keys hash for this user
    ssh_users.each do |ssh_user|
      users[ssh_user]['name'] ||= ssh_user
      ::Dust.print_msg "adding user #{users[ssh_user]['name']}", :indent => 2
      users[ssh_user]['keys'].each do |key|
        authorized_keys.concat"#{key}"
        authorized_keys.concat " #{users[ssh_user]['name']}" if users[ssh_user]['name']
        authorized_keys.concat " <#{users[ssh_user]['email']}>" if users[ssh_user]['email']
        authorized_keys.concat "\n"
      end
      ::Dust.print_ok
    end

    authorized_keys    
  end
  
  # deploy the authorized_keys file for this user
  # creating user if not existent
  def deploy_authorized_keys user, authorized_keys
    # create user, if not existent
    next unless @node.create_user user
    
    home = @node.get_home user
    # check and create necessary directories
    next unless @node.mkdir("#{home}/.ssh")
    
    # deploy authorized_keys
    next unless @node.write "#{home}/.ssh/authorized_keys", authorized_keys
    
    # check permissions
    @node.chown "#{user}:#{user}", "#{home}/.ssh"
    @node.chmod '0644', "#{home}/.ssh/authorized_keys"    
  end
  
  # remove authorized_keys files for all other users  
  # TODO: add this option  
  def cleanup
    if options.cleanup?
      ::Dust.print_msg "deleting other authorized_keys files\n"
      @node.get_system_users(:quiet => true).each do |user|
        next if users.keys.include? user
        home = @node.get_home user
        if @node.file_exists? "#{home}/.ssh/authorized_keys", :quiet => true
          @node.rm "#{home}/.ssh/authorized_keys", :indent => 2
        end
      end
    end
  end
end
