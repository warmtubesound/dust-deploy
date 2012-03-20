class Duplicity < Recipe
  desc 'duplicity:deploy', 'installs and configures duplicity backups'
  def deploy
    return unless @node.install_package 'duplicity'

    # clear all other duplicity cronjobs that might have been deployed earlier
    remove_duplicity_cronjobs

    # return if config simply says 'remove'
    return if @config == 'remove'

    @config.each do |scenario, c|
      # cloning is necessary if we have configurations with multiple hostnames
      config = default_config.merge c

      # if directory config options is not given, use hostname-scenario
      config['directory'] ||= "#{@node['hostname']}-#{scenario}"

      # check whether backend is specified, skip to next scenario if not
      unless config['backend'] and config['passphrase']
        ::Dust.print_failed "scenario #{scenario}: backend or passphrase missing.", 1
        next
      end

      # check if interval is correct
      unless [ 'monthly', 'weekly', 'daily', 'hourly' ].include? config['interval']
        return ::Dust.print_failed "invalid interval: '#{config['interval']}'"
      end

      # check whether we need ncftp
      @node.install_package 'ncftp' if config['backend'].include? 'ftp://'

      # scp backend on centos needs python-pexpect (not needed anymore for newer systems)
      # @node.install_package 'python-pexpect' if config['backend'].include? 'scp://' and @node.uses_rpm?

      # add hostkey to known_hosts
      if config['hostkey']
        ::Dust.print_msg 'checking if ssh key is in known_hosts'
        unless ::Dust.print_result @node.exec("grep -q '#{config['hostkey']}' /root/.ssh/known_hosts")[:exit_code] == 0
          @node.mkdir '/root/.ssh', :indent => 2
          @node.append '/root/.ssh/known_hosts', "#{config['hostkey']}\n", :indent => 2
        end
      end

      # generate path for the cronjob
      cronjob_path = "/etc/cron.#{config['interval']}/duplicity-#{scenario}"

      # adjust and upload cronjob
      ::Dust.print_msg "adjusting and deploying cronjob (scenario: #{scenario}, interval: #{config['interval']})\n"
      config['options'].to_array.each { |option| ::Dust.print_ok "adding option: #{option}", :indent => 2 }

      @node.deploy_file "#{@template_path}/cronjob", cronjob_path, :binding => binding

      # making cronjob executeable
      @node.chmod '0700', cronjob_path
      puts
    end
  end


  # print duplicity-status
  desc 'duplicity:status', 'displays current status of all duplicity backups'
  def status
    return unless @node.package_installed? 'duplicity'

    @config.each do |scenario, c|
      config = default_config.merge c

      # if directory config option is not given, use hostname-scenario
      config['directory'] ||= "#{@node['hostname']}-#{scenario}"

      # check whether backend is specified, skip to next scenario if not
      return ::Dust.print_failed 'no backend specified.' unless config['backend']

      ::Dust.print_msg "running collection-status for scenario '#{scenario}'"
      cmd = "nice -n #{config['nice']} duplicity collection-status " +
            "--archive-dir #{config['archive']} " +
            "#{File.join(config['backend'], config['directory'])}"

      cmd += " |tail -n3 |head -n1" unless options.long?

      ret = @node.exec cmd

      # check exit code and stdout shouldn't be empty
      ::Dust.print_result( (ret[:exit_code] == 0 and ret[:stdout].length > 0) )

      if options.long?
        ::Dust.print_msg "#{::Dust.black}#{ret[:stdout]}#{::Dust.none}", :indent => 0
      else
        ::Dust.print_msg "\t#{::Dust.black}#{ret[:stdout].sub(/^\s+([a-zA-Z]+)\s+(\w+\s+\w+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(\d+)$/, 'Last backup: \1 (\3 sets) on \2')}#{::Dust.none}", :indent => 0
      end

      puts
    end
  end

  private
  def default_config
    {
      'interval' => 'daily',
      'nice' => 10,
      'keep-n-full' => 5,
      'full-if-older-than' => '7D',
      'archive' => '/tmp/duplicity',
      'options' => [],
      'include' => [],
      'exclude' => []
    }
  end


  # removes all duplicity cronjobs
  def remove_duplicity_cronjobs
    ::Dust.print_msg 'deleting old duplicity cronjobs'
    @node.rm '/etc/cron.*/duplicity*', :quiet => true
    ::Dust.print_ok
  end

end
