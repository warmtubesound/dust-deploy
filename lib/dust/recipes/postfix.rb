class Postfix < Recipe
  desc 'postfix:deploy', 'installs and configures postfix mail server'
  def deploy
    @config = default_config.merge @config
    @config.boolean_to_string! # parse 'no/yes' as string, not as boolean
    
    return unless @node.install_package @config['package']

    if @config['main.cf']
      main_cf = ''
      @config['main.cf'].each { |key, value| main_cf << "#{key} = #{value}\n" }
      @node.write "#{@config['etc_dir']}/main.cf", main_cf
    end

    if @config['master.cf']
      master_cf = ''
      @config['master.cf'].each do |s|
        return @node.messages.add("service missing: #{s.inspect}").failed unless s['service']
        s = default_service(s['service']).merge s

        master_cf << "#{s['service']} #{s['type']} #{s['private']} " +
                     "#{s['unpriv']} #{s['chroot']} #{s['wakeup']} " +
                     "#{s['maxproc']} #{s['command']}\n"
        s['args'].to_array.each { |a|  master_cf << "  #{a}\n" } if s['args']
      end

      @node.write "#{@config['etc_dir']}/master.cf", master_cf
    end

    @node.restart_service @config['service'] if @options.restart?
    @node.reload_service @config['service'] if @options.reload?
  end


  private

  # default dust configuration
  def default_config
    { 'package' => 'postfix', 'etc_dir' => '/etc/postfix', 'service' => 'postfix' }
  end

  # master.cf default service configuration
  def default_service(service)
    { 'type' => 'unix', 'private' => '-', 'unpriv' => '-', 'chroot' => '-',
      'wakeup' => '-', 'maxproc' => '-', 'command' => service }
  end
end
