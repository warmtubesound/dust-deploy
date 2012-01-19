class Sshd < Recipe
  
  desc 'sshd:deploy', 'installs and configures the ssh server'
  def deploy 
    return unless @node.install_package 'openssh-server'

    generate_default_config
    @config.values_to_array!

    check_hostkeys
    apply_configuration

    @node.write '/etc/ssh/sshd_config', @sshd_config
    restart_daemon
  end


  private

  def default_config
    { 'Port' => 22,
      'Protocol' => 2,
      'AcceptEnv' => 'LANG LC_*',
      'HostKey' => [ '/etc/ssh/ssh_host_dsa_key',
                     '/etc/ssh/ssh_host_ecdsa_key',
                      '/etc/ssh/ssh_host_rsa_key' ],
      'PasswordAuthentication' => 'yes', 
      'ChallengeResponseAuthentication' => 'no',
      'X11Forwarding' => 'yes',
      'UsePAM' => 'yes',
      'SyslogFacility' => 'AUTH',
      'GSSAPIAuthentication' => 'no'
    }
  end

  def generate_default_config
    @config = default_config.merge @config

    unless @config['sftp']
      @config['Subsystem'] ||= 'sftp /usr/lib/openssh/sftp-server' if @node.uses_apt?
      @config['Subsystem'] ||= 'sftp /usr/libexec/openssh/sftp-server' if @node.uses_rpm?
    end

    if @node.uses_rpm?
      @config['SyslogFacility'] ||= 'AUTHPRIV'
      @config['GSSAPIAuthentication'] ||= 'yes'
    end

    if @node.uses_apt?
      @config['PrintMotd'] ||= 'no'
    end
  end

  def apply_configuration
    @sshd_config = ''
    @config.each do |key, values|
      values.each { |value| @sshd_config.concat "#{key} #{value}\n" }
    end
  end

  def check_hostkeys
    @config['HostKey'].each do |hostkey|
      unless @node.file_exists? hostkey, :quiet => true
        ::Dust.print_warning "hostkey '#{hostkey}' not found. removing from config"
        @config['HostKey'].delete hostkey
      end
    end
  end

  def restart_daemon
    daemon = 'ssh' if @node.uses_apt?
    daemon = 'sshd' if @node.uses_rpm?

    @node.restart_service daemon if @options.restart
    @node.reload_service daemon if @options.reload
  end
end
