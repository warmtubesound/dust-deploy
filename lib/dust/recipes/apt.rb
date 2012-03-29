class Apt < Recipe
  desc 'apt:deploy', 'configures apt/aptitude'
  def deploy
    return unless @node.uses_apt? 

    @config = default_config.merge @config

    unattended_upgrades @config.delete('unattended_upgrades')
    proxy @config.delete('proxy')

    @config.each do |name, settings|
      ::Dust.print_msg "deploying apt settings #{name}\n"
      conf = ''
      settings.to_array.each do |setting|
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

    ::Dust.print_msg "deploying unattended upgrades configuration\n"
    periodic = ''
    periodic << "APT::Periodic::Enable \"#{config['enable']}\";\n"
    periodic << "APT::Periodic::Update-Package-Lists \"#{config['update-package-lists']}\";\n"
    periodic << "APT::Periodic::Unattended-Upgrade \"#{config['unattended-upgrade']}\";\n"
    periodic << "APT::Periodic::AutocleanInterval \"#{config['autocleaninterval']}\";\n"
    periodic << "APT::Periodic::Verbose \"#{config['verbose']}\";\n"

    @node.write '/etc/apt/apt.conf.d/02periodic', periodic, :indent => 2
  end

  def proxy config
    return if config.is_a? FalseClass or config == 'disabled'
    
    ::Dust.print_msg "deploying proxy configuration\n"
    proxy = "Acquire::http::Proxy \"#{config}\";\n"

    @node.write '/etc/apt/apt.conf.d/02proxy', proxy, :indent => 2
  end
end
