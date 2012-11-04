require 'erb'

class Nginx < Recipe
  desc 'nginx:deploy', 'installs and configures nginx web server'
  def deploy
    # default package to install
    @config['package'] ||= 'nginx'
    @config['user'] ||= 'nginx' if @node.uses_rpm?
    @config['user'] ||= 'www-data' if @node.uses_apt?

    Array(@config['package']).each do |package|
      return unless @node.install_package(package)
    end

    @node.mkdir('/etc/nginx')
    @node.mkdir('/etc/nginx/sites-enabled')
    @node.mkdir('/etc/nginx/sites-available')

    @node.deploy_file("#{@template_path}/nginx.conf", '/etc/nginx/nginx.conf', :binding => binding)

    # remove old sites that may be present
    msg = @node.messages.add('deleting old sites in /etc/nginx/sites-*')
    @node.rm '/etc/nginx/sites-*/*', :quiet => true
    msg.ok

    @config['sites'].each do |state, sites|
      Array(sites).each do |site|
        @node.deploy_file("#{@template_path}/sites/#{site}", "/etc/nginx/sites-available/#{site}", :binding => binding)

        # symlink to sites-enabled if this is listed as an enabled site
        if state == 'enabled'
          msg = @node.messages.add("enabling #{site}", :indent => 2)
          msg.parse_result(@node.exec("cd /etc/nginx/sites-enabled && ln -s ../sites-available/#{site} #{site}")[:exit_code])
        end
      end
    end

    # deploy ssl certificates to /etc/nginx/certs
    @config['certs'] ||= []
    Array(@config['certs']).each do |file|
      # file can either be
      # a string 'file': file is just copied over
      # a hash { 'source': 'target' } when source and target filename differ

      if file.is_a? String
        source = "#{@template_path}/certs/#{file}"
        destination = "/etc/nginx/certs/#{File.basename(file)}"

      elsif file.is_a? Hash
        source = "#{@template_path}/certs/#{File.basename(file.keys.first)}"
        destination = "/etc/nginx/certs/#{File.basename(file.values.first)}"

      else
        return @node.messages.add("#{file.inspect} is neither String nor Hash!").failed
      end

      unless File.exists?(source)
        @node.messages.add("#{source} not found. skipping.").warning
        next
      end

      @node.mkdir(File.dirname(destination))
      @node.deploy_file(source, destination)
      @node.chown("#{@config['user']}:#{@node.get_gid(@config['user'])}", destination)
      @node.chmod('0600', destination)
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
