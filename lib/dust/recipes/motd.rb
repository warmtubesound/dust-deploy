class Motd < Recipe
  desc 'motd:deploy', 'creates message of the day'
  def deploy    
    @node.deploy_file "#{@template_path}/motd", '/etc/motd', :binding => binding
  end
  
  desc 'motd:status', 'shows current message of the day'
  def status
    msg = @node.messages.add('getting /etc/motd')
    ret = @node.exec 'cat /etc/motd'
    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end  
end
