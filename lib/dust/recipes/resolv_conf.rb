class ResolvConf < Recipe
  desc 'resolv_conf:deploy', 'configures /etc/resolv.conf'
  def deploy 
    ::Dust.print_msg "configuring resolv.conf\n"

    # if config is just true, create empty hash and use defaults
    @config = {} unless @config.is_a? Hash

    # setting default config variables (unless already set)
    @config['nameservers'] ||= [ '208.67.222.222', '208.67.220.220' ] # opendns

    config_file = ''

    # configures whether daily reports are sent
    if @config['search']
      ::Dust.print_msg "adding search #{@config['search']}", :indent => 2
      config_file += "search #{@config['search']}\n"
      ::Dust.print_ok
    end

    if @config['domain']
      ::Dust.print_msg "adding domain #{@config['domain']}", :indent => 2
      config_file += "domain #{@config['domain']}\n"
      ::Dust.print_ok
    end

    if @config['options']
      ::Dust.print_msg "adding options #{@config['options']}", :indent => 2
      config_file += "options #{@config['options']}\n"
      ::Dust.print_ok
    end

    @config['nameservers'].each do |nameserver|
      ::Dust.print_msg "adding nameserver #{nameserver}", :indent => 2
      config_file += "nameserver #{nameserver}\n"
      ::Dust.print_ok
    end
 
    @node.write '/etc/resolv.conf', config_file
  end
  
  desc 'resolv_conf:status', 'shows current /etc/resolv.conf'
  def status
    ::Dust.print_msg 'getting /etc/resolv.conf'
    ret = @node.exec 'cat /etc/resolv.conf'
    ::Dust.print_result ret[:exit_code]
    ::Dust.print_ret ret
  end  
end
