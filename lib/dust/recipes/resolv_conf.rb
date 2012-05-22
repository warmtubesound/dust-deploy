class ResolvConf < Recipe
  desc 'resolv_conf:deploy', 'configures /etc/resolv.conf'
  def deploy
    msg = @node.messages.add("configuring resolv.conf\n")

    # if config is just true, create empty hash and use defaults
    @config = {} unless @config.is_a? Hash

    # setting default config variables (unless already set)
    @config['nameservers'] ||= [ '208.67.222.222', '208.67.220.220' ] # opendns

    config_file = ''

    # configures whether daily reports are sent
    if @config['search']
      msg = @node.messages.add("adding search #{@config['search']}", :indent => 2)
      config_file << "search #{@config['search']}\n"
      msg.ok
    end

    if @config['domain']
      msg = @node.messages.add("adding domain #{@config['domain']}", :indent => 2)
      config_file << "domain #{@config['domain']}\n"
      msg.ok
    end

    if @config['options']
      msg = @node.messages.add("adding options #{@config['options']}", :indent => 2)
      config_file << "options #{@config['options']}\n"
      msg.ok
    end

    @config['nameservers'].each do |nameserver|
      msg = @node.messages.add("adding nameserver #{nameserver}", :indent => 2)
      config_file << "nameserver #{nameserver}\n"
      msg.ok
    end

    @node.write '/etc/resolv.conf', config_file
  end

  desc 'resolv_conf:status', 'shows current /etc/resolv.conf'
  def status
    msg = @node.messages.add('getting /etc/resolv.conf')
    ret = @node.exec 'cat /etc/resolv.conf'
    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end
end
