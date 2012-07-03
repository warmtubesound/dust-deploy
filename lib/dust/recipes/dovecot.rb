class Dovecot < Recipe
  desc 'dovecot:deploy', 'installs and configures dovecot imap/pop server'
  def deploy
    @config = default_config.merge @config
    @config.boolean_to_string! # parse 'no/yes' as string, not as boolean

    # stip non-config-file values from @config
    service = @config.delete('service')
    package = @config.delete('package')
    etc_dir = @config.delete('etc_dir')

    package.to_array.each do |pkg|
      return unless @node.install_package(pkg)
    end

    @config.each do |name, config|
      msg = @node.messages.add("configuring #{name}")
      msg.ok
      @node.write "#{etc_dir}/#{name}", generate_config(config)
    end

    @node.restart_service(service) if @options.restart?
  end


  private

  def generate_config(config, indent = 0)
    s = ''
    config.each do |key, value|
      if value.is_a? Hash
        s << '    ' * indent
        s << "#{key} {\n"
        s << generate_config(value, indent + 1)
        s << '    ' * indent
        s << "}\n"
      else
        s << '    ' * indent
        s << "#{key} = #{value}\n"
      end
    end

    s
  end

  # default dust configuration
  def default_config
    { 'package' => 'dovecot', 'etc_dir' => '/etc/dovecot', 'service' => 'dovecot' }
  end

  # master.cf default service configuration
  def default_service(service)
    { 'type' => 'unix', 'private' => '-', 'unpriv' => '-', 'chroot' => '-',
      'wakeup' => '-', 'maxproc' => '-', 'command' => service }
  end
end
