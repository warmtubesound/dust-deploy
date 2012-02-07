class CupsClient < Recipe
  desc 'cups_client:deploy', 'maintains /etc/cups/client.conf'
  def deploy 
    return false unless install
    
    return ::Dust.print_failed 'no printserver specified.' unless @config
    
    ::Dust.print_ok "setting servername to: #{@config}"
    @node.write '/etc/cups/client.conf', "ServerName #{@config}\n"
  end
  
  desc 'cups_client:status', 'shows current /etc/cups/client.conf'
  def status
    ::Dust.print_msg 'getting /etc/cups/client.conf'
    ret = @node.exec 'cat /etc/cups/client.conf'
    ::Dust.print_result ret[:exit_code]
    ::Dust.print_ret ret
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

