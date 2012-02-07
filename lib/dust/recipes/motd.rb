class Motd < Recipe
  desc 'motd:deploy', 'creates message of the day'
  def deploy    
    @node.deploy_file "#{@template_path}/motd", '/etc/motd', :binding => binding
  end
  
  desc 'motd:status', 'shows current message of the day'
  def status
    ::Dust.print_msg 'getting /etc/motd'
    ret = @node.exec 'cat /etc/motd'
    ::Dust.print_result ret[:exit_code]
    ::Dust.print_ret ret
  end  
end
