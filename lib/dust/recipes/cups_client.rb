class CupsClient < Recipe
  desc 'cups_client:deploy', 'maintains /etc/cups/client.conf'
  def deploy 
    return @node.messages.add('no printserver specified.').failed unless @config

    if @config == 'remove'
      @node.rm('/etc/cups/client.conf')
    else
      return false unless install
      @node.messages.add("setting servername to: #{@config}").ok
      @node.write '/etc/cups/client.conf', "ServerName #{@config}\n"
    end
  end
  
  desc 'cups_client:status', 'shows current /etc/cups/client.conf'
  def status
    msg = @node.messages.add('getting /etc/cups/client.conf')
    ret = @node.exec 'cat /etc/cups/client.conf'
    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end
  
  private
  
  def install
    if @node.uses_apt?
      return false unless @node.install_package 'cups-client'
      return false unless @node.install_package 'cups-bsd'      
    
    elsif @node.uses_rpm?
      return false unless @node.install_package 'cups'
    end
    
    true
  end
end
