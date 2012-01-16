class Aliases < Recipe
  desc 'aliases:deploy', 'installs email aliases'
  def deploy 
    return unless @node.package_installed? 'postfix'
    
    @node.deploy_file "#{@template_path}/aliases", '/etc/aliases', :binding => binding

    ::Dust.print_msg 'running newaliases'
    ::Dust.print_result @node.exec('newaliases')[:exit_code]
  end
end

