class EtcHosts < Recipe
  desc 'etc_hosts:deploy', 'deploys /etc/hosts'
  def deploy
    @node.deploy_file "#{@template_path}/hosts", '/etc/hosts', :binding => binding

    # restart dns service
    if @options.restart? and @config.is_a? String
      @node.package_installed? @config
      @node.restart_service @config
    end
  end

  desc 'etc_hosts:status', 'shows current /etc/hosts'
  def status
    msg = @node.messages.add('getting /etc/hosts')
    ret = @node.exec 'cat /etc/hosts'
    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end
end
