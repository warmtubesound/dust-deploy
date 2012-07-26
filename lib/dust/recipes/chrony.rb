class Chrony < Recipe
  desc 'chrony:deploy', 'installs and configures chrony'
  def deploy
    # warn if other ntp package is installed
    [ 'openntpd', 'ntp' ].each do |package|
      if @node.package_installed?(package, :quiet => true)
        @node.messages.add("#{package} installed, might conflict with chrony, might get deleted").warning
      end
    end

    # install package
    return false unless @node.install_package('chrony')

    # set config file and service name according to distribution used
    if @node.uses_apt?
      config = '/etc/chrony/chrony.conf'
      service = 'chrony'
    elsif @node.uses_rpm?
      config = '/etc/chrony.conf'
      service = 'chronyd'
    end

    @node.write(config, generate_config)

    # centos systems don't use -r by default
    @node.write('/etc/sysconfig/chronyd', 'OPTIONS="-u chrony -r"' + "\n") if @node.uses_rpm?

    @node.autostart_service(service)
    @node.restart_service(service) if options.restart?
  end


  private

  # generate chrony.conf
  def generate_config
    @config = default_options.merge(@config)
    file = ''
    @config.each do |key, value|
      Array(value).each { |v| file << "#{key} #{v}\n" }
    end
    file
  end

  # default chrony.conf options
  def default_options
    options = {
      'server' => [
        '0.pool.ntp.org minpoll 8',
        '1.pool.ntp.org minpoll 8',
        '2.pool.ntp.org minpoll 8',
        '3.pool.ntp.org minpoll 8'
      ],
      'commandkey' => 1,
      'logdir' => '/var/log/chrony',
      'logchange' => 0.5,
      'maxupdateskew' => 100.0,       # Stop bad estimates upsetting machine clock.
      'dumponexit' => '',             # Dump measurements when daemon exits.
      'dumpdir' => '/var/lib/chrony'
    }

    if @node.uses_rpm?
      options['keyfile'] = '/etc/chrony.keys'
      options['driftfile'] = '/var/lib/chrony/drift'
    elsif @node.uses_apt?
      options['keyfile'] = '/etc/chrony/chrony.keys'
      options['driftfile'] = '/var/lib/chrony/chrony.drift'
    end

    options
  end
end

