class Nginx < Recipe
  desc 'nginx:deploy', 'installs and configures nginx web server'
  def deploy
    # default package to install
    @config['package'] ||= 'nginx'

    @config['package'].to_array.each do |package|
      return unless @node.install_package(package)
    end

    @node.deploy_file("#{@template_path}/nginx.conf", '/etc/nginx/nginx.conf', :binding => binding)

    # remove old sites that may be present
    msg = @node.messages.add('deleting old sites in /etc/nginx/sites-*')
    @node.rm '/etc/nginx/sites-*/*', :quiet => true
    msg.ok

    @config['sites'].each do |state, sites|
      sites.to_array.each do |site|
        @node.deploy_file("#{@template_path}/sites/#{site}", "/etc/nginx/sites-available/#{site}", :binding => binding)

        # symlink to sites-enabled if this is listed as an enabled site
        if state == 'enabled'
          msg = @node.messages.add("enabling #{site}", :indent => 2)
          msg.parse_result(@node.exec("cd /etc/nginx/sites-enabled && ln -s ../sites-available/#{site} #{site}")[:exit_code])
        end
      end
    end

    # check configuration and restart nginx
    msg = @node.messages.add('checking nginx configuration')
    ret = @node.exec('/etc/init.d/nginx configtest')
    if ret[:exit_code] == 0
      msg.ok
      @node.restart_service('nginx') if options.restart?
    else
      msg.failed("\n" + ret[:stderr])
    end
  end

  desc 'nginx:status', 'displays nginx status'
  def status
    @node.print_service_status 'nginx'
  end
end
