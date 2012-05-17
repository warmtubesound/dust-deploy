class Aliases < Recipe
  desc 'aliases:deploy', 'installs email aliases'
  def deploy 
    return unless @node.package_installed? 'postfix'
    
    @node.deploy_file "#{@template_path}/aliases", '/etc/aliases', :binding => binding

    msg = @node.messages.add('running newaliases')
    msg.parse_result(@node.exec('newaliases')[:exit_code])
  end
  
  desc 'aliases:status', 'shows current aliases'
  def status
    msg = @node.messages.add('getting /etc/aliases')
    ret = @node.exec 'cat /etc/aliases'
    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end
end
