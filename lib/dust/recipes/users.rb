class Users < Recipe

  desc 'users:deploy', 'creates users and user settings (incl. ssh keys)'
  def deploy
    @config.each do |user, options|
      # just create the user, without any arguments
      options = {} if options.nil? or options.is_a? TrueClass
      next unless @node.manage_user(user, options)

      # don't deploy anything if the user just has been removed
      unless options['remove']
        deploy_ssh_keys(user, options['ssh_keys']) if options['ssh_keys']
        deploy_authorized_keys(user, options['authorized_keys']) if options['authorized_keys']
      end
   end
  end


  private

  # deploys ssh keys to users homedir
  def deploy_ssh_keys(user, key_dir)
    ssh_dir = create_ssh_dir(user)
    @node.messages.add("deploying ssh keys for #{user}\n")

    Dir["#{@template_path}/#{key_dir}/*"].each do |file|
      destination = "#{ssh_dir}/#{File.basename(file)}"
      @node.scp(file, destination, :indent => 2)
      @node.chown("#{user}:#{@node.get_gid(user)}", destination)

      # chmod private key
      if File.basename(file) =~ /^(id_rsa|id_dsa|id_ecdsa)$/
        msg = @node.messages.add('setting private key access to 0600', :indent => 3)
        msg.parse_result(@node.chmod('0600', destination, :quiet => true))
      end
    end
  end

  # generates and deploy authorized_keys to users homedir
  def deploy_authorized_keys(user, ssh_users)
    @node.messages.add("generating authorized_keys for #{user}\n")
    ssh_dir = create_ssh_dir(user)

    authorized_keys = generate_authorized_keys(ssh_users)
    return false unless authorized_keys

    @node.write("#{ssh_dir}/authorized_keys", authorized_keys)
    @node.chown("#{user}:#{@node.get_gid(user)}", "#{ssh_dir}/authorized_keys")
    @node.chcon({ 'type' => 'ssh_home_t' }, "#{ssh_dir}/authorized_keys")
  end

  def create_ssh_dir(user)
    ssh_dir = @node.get_home(user) + '/.ssh'
    @node.mkdir(ssh_dir)
    @node.chown("#{user}:#{@node.get_gid(user)}", ssh_dir)
    @node.chcon({ 'type' => 'ssh_home_t' }, ssh_dir)
    ssh_dir
  end

  def generate_authorized_keys(ssh_users)
    # load users and their ssh keys from yaml file
    unless File.exists?("#{@template_path}/public_keys.yaml")
      return @node.messages.add("#{@template_path}/public_keys.yaml not present").failed
    end

    users = YAML.load_file("#{@template_path}/public_keys.yaml")
    authorized_keys = ''

    # create the authorized_keys hash for this user
    ssh_users.to_array.each do |ssh_user|
      unless users[ssh_user]
        return @node.messages.add("#{ssh_user} cannot be found in #{@template_path}/public_keys.yaml").failed
      end

      users[ssh_user]['name'] ||= ssh_user
      msg = @node.messages.add("adding user #{users[ssh_user]['name']}", :indent => 2)
      users[ssh_user]['keys'].each do |key|
        authorized_keys << "#{key}"
        authorized_keys << " #{users[ssh_user]['name']}" if users[ssh_user]['name']
        authorized_keys << " <#{users[ssh_user]['email']}>" if users[ssh_user]['email']
        authorized_keys << "\n"
      end
      msg.ok
    end

    authorized_keys
  end
end
