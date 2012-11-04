class Ssh_config < Recipe

  desc 'ssh_config:deploy', 'deploys /etc/ssh/ssh_config'
  def deploy
    return unless install
    @config = @config.deep_merge(default_config)
    @node.write('/etc/ssh/ssh_config', generate_ssh_config)
  end


  private

  def install
    return @node.install_package('openssh-client') if @node.uses_apt?
    return @node.install_package('openssh-clients') if @node.uses_rpm?
    return @node.install_package('openssh') if @node.uses_pacman?
    false
  end

  def default_config
    { 'Host *' =>
      {
        'ForwardX11Trusted' => 'yes',
        'SendEnv' => [ 'LANG LC_*', 'XMODIFIERS' ],
        'HashKnownHosts' => 'yes',
        'GSSAPIAuthentication' => 'yes',
        'GSSAPIDelegateCredentials' => 'no'
      }
    }
  end

  def generate_ssh_config
    ssh_config = ''
    @config.each do |key, value|

      # hashes are blocks, indent them
      if value.is_a? Hash
        ssh_config << "#{key}\n"
        value.each do |k, v|
          Array(v).each { |x| ssh_config << "    #{k} #{x}\n" }
        end
      else
        Array(value).each { |x| ssh_config << "#{key} #{x}\n" }
      end
    end
    ssh_config
  end
end
