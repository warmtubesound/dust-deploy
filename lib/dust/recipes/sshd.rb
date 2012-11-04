class Sshd < Recipe

  desc 'sshd:deploy', 'installs and configures the ssh server'
  def deploy
    if @node.uses_pacman?
      return unless @node.install_package 'openssh'
    else
      return unless @node.install_package 'openssh-server'
    end

    generate_default_config

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
    @config.boolean_to_string!
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
    conditional_blocks = ''

    @config.each do |key, value|

      # hashes are conditional blocks
      # which have to be placed at the end of the file
      if value.is_a? Hash
        value.each do |k, v|
          conditional_blocks << "#{key} #{k}\n"
          Array(v).each { |x, y| conditional_blocks << "    #{x} #{y}\n" }
        end

      else
        Array(value).each { |value| @sshd_config << "#{key} #{value}\n" }
      end
    end

    # append conditional blocks
    @sshd_config << conditional_blocks
  end

  def check_hostkeys
    @config['HostKey'].each do |hostkey|
      unless @node.file_exists? hostkey, :quiet => true
        @node.messages.add("hostkey '#{hostkey}' not found. removing from config").warning
        @config['HostKey'].delete hostkey
      end
    end
  end

  def restart_daemon
    if @node.uses_apt?
      daemon = 'ssh'
    else
      daemon = 'sshd'
    end

    @node.restart_service daemon if @options.restart
    @node.reload_service daemon if @options.reload
  end
end
