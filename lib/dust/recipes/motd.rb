class Motd < Recipe
  desc 'motd:deploy', 'creates message of the day'
  def deploy    
    @node.deploy_file "#{@template_path}/motd", '/etc/motd', :binding => binding
  end
end
