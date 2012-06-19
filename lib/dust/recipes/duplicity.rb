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
        @node.messages.add("scenario #{scenario}: backend or passphrase missing.").failed
        next
      end

      # check if interval is correct
      unless [ 'monthly', 'weekly', 'daily', 'hourly' ].include? config['interval']
        return @node.messages.add("invalid interval: '#{config['interval']}'").failed
      end

      # check whether we need ncftp
      @node.install_package 'ncftp' if config['backend'].include? 'ftp://'

      # scp backend on centos needs python-paramiko
      @node.install_package 'python-paramiko' if @node.uses_rpm? and config['backend'].include? 'scp://'

      # scp backend on centos needs python-pexpect (not needed anymore for newer systems)
      # @node.install_package 'python-pexpect' if config['backend'].include? 'scp://' and @node.uses_rpm?

      # add hostkey to known_hosts
      if config['hostkey']
        msg = @node.messages.add('checking if ssh key is in known_hosts')
        unless msg.parse_result(@node.exec("grep -q '#{config['hostkey']}' /root/.ssh/known_hosts")[:exit_code] == 0)
          @node.mkdir '/root/.ssh', :indent => 2
          @node.append '/root/.ssh/known_hosts', "#{config['hostkey']}\n", :indent => 2
        end
      end

      # generate path for the cronjob
      cronjob_path = "/etc/cron.#{config['interval']}/duplicity-#{scenario}"

      # adjust and upload cronjob
      @node.messages.add("adjusting and deploying cronjob (scenario: #{scenario}, interval: #{config['interval']})\n")
      config['options'].to_array.each { |option| @node.messages.add("adding option: #{option}", :indent => 2).ok }

      @node.deploy_file "#{@template_path}/cronjob", cronjob_path, :binding => binding

      # making cronjob executeable
      @node.chmod '0700', cronjob_path
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
      return @node.messages.add('no backend specified.').failed unless config['backend']

      msg = @node.messages.add("running collection-status for scenario '#{scenario}'")
      cmd = "nice -n #{config['nice']} duplicity collection-status " +
            "--archive-dir #{config['archive']} " +
            "#{File.join(config['backend'], config['directory'])}"

      cmd << " |tail -n3 |head -n1"

      ret = @node.exec cmd

      # check exit code and stdout shouldn't be empty
      msg.parse_result( (ret[:exit_code] == 0 and ret[:stdout].length > 0) )

      # parse backup type, date and number of sets
      m = ret[:stdout].match(/^\s+([a-zA-Z]+)\s+(\w+\s+\w+\s+\d+\s+\d+:\d+:\d+\s+\d+)\s+(\d+)$/)

      if m
        type, date, sets = m[1..3]
        @node.messages.add("Last backup: #{type} (#{sets} sets) on #{date}", :indent => 2).ok
      else
        @node.messages.add('could not get backup chain', :indent => 2).failed
      end

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
    msg = @node.messages.add('deleting old duplicity cronjobs')
    @node.rm '/etc/cron.*/duplicity*', :quiet => true
    msg.ok
  end

end
