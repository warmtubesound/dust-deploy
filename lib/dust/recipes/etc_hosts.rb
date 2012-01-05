class EtcHosts < Thor
  desc 'etc_hosts:deploy', 'deploys /etc/hosts'
  def deploy node, daemon, options
    template_path = "./templates/#{ File.basename(__FILE__).chomp( File.extname(__FILE__) ) }"

    node.scp("#{template_path}/hosts", '/etc/hosts')

    # restart dns service
    if options.restart? and daemon.is_a? String
      node.package_installed? daemon
      node.restart_service daemon if options.restart?
    end
  end
end

