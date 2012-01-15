class EtcHosts < Recipe
  desc 'etc_hosts:deploy', 'deploys /etc/hosts'
  def deploy
    @node.scp "#{@template_path}/hosts", '/etc/hosts'

    # restart dns service
    if @options.restart? and @config.is_a? String
      @node.package_installed? @config
      @node.restart_service @config
    end
  end
end

