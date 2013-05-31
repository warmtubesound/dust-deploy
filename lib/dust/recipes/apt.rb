class Apt < Recipe
  desc 'apt:deploy', 'configures apt'
  def deploy
    return unless @node.uses_apt?

    @config = default_config.merge @config

    unattended_upgrades @config.delete('unattended_upgrades')
    proxy @config.delete('proxy')

    @config.each do |name, settings|
      @node.messages.add("deploying apt settings #{name}\n")
      conf = ''
      Array(settings).each do |setting|
        conf << "#{setting}\n"
      end

      @node.write "/etc/apt/apt.conf.d/#{name}", conf, :indent => 2
    end
  end


  private
  def default_config
    {
      'unattended_upgrades' => {
        'enable' => 1,
        'update-package-lists' => 1,
        'unattended-upgrade' => 1,
        'autocleaninterval' => 1,
        'verbose' => 0
      },

      'proxy' => 'disabled'
    }
  end

  def unattended_upgrades config
    return if config.is_a? FalseClass or config == 'disabled'

    @node.install_package 'unattended-upgrades'

    @node.messages.add("deploying unattended upgrades configuration\n")
    periodic = ''
    periodic << "APT::Periodic::Enable \"#{config['enable']}\";\n"
    periodic << "APT::Periodic::Update-Package-Lists \"#{config['update-package-lists']}\";\n"
    periodic << "APT::Periodic::Unattended-Upgrade \"#{config['unattended-upgrade']}\";\n"
    periodic << "APT::Periodic::AutocleanInterval \"#{config['autocleaninterval']}\";\n"
    periodic << "APT::Periodic::Verbose \"#{config['verbose']}\";\n"

    @node.write '/etc/apt/apt.conf.d/02periodic', periodic, :indent => 2
  end

  def proxy config
    # look for already configured proxy and delete
    files = @node.exec("grep -v '^#' /etc/apt/ -R |grep -i 'acquire::http::proxy' |cut -d: -f1")[:stdout]
    files.each_line do |file|
      file.chomp!

      # skip 02proxy, because we're going to overwrite it anyways
      next if file == '/etc/apt/apt.conf.d/02proxy'

      @node.messages.add("found proxy configuration in file #{file}, commenting out").warning
      @node.exec "sed -i 's/^\\(acquire::http::proxy.*\\)/#\\1/i' #{file}"
    end

    return if config.is_a? FalseClass or config == 'disabled'

    @node.messages.add("deploying proxy configuration\n")
    proxy = "Acquire::http::Proxy \"#{config}\";\n"

    @node.write '/etc/apt/apt.conf.d/02proxy', proxy, :indent => 2
  end
end
