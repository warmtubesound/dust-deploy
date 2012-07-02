require 'ipaddress'

class Iptables < Recipe

  desc 'iptables:deploy', 'configures iptables firewall'
  def deploy
    # list of all tables and chains
    @tables = {}
    @tables['ipv4'] = {}
    @tables['ipv4']['filter'] = [ 'INPUT', 'OUTPUT', 'FORWARD' ]
    @tables['ipv4']['nat'] = [ 'OUTPUT', 'PREROUTING', 'POSTROUTING' ]
    @tables['ipv4']['mangle'] = [ 'INPUT', 'OUTPUT', 'FORWARD', 'PREROUTING', 'POSTROUTING' ]
    @tables['ipv4']['raw'] = [ 'OUTPUT', 'PREROUTING' ]

    @tables['ipv6'] = {}
    @tables['ipv6']['filter'] = [ 'INPUT', 'OUTPUT', 'FORWARD' ]
    @tables['ipv6']['mangle'] = [ 'INPUT', 'OUTPUT', 'FORWARD', 'PREROUTING', 'POSTROUTING' ]
    @tables['ipv6']['raw'] = [ 'OUTPUT', 'PREROUTING' ]

    return unless install

    # remove iptables scripts from old dust versions
    remove_old_scripts

    [4, 6].each do |v|
      @script = ''
      @ip_version = v

      @node.messages.add("generating ipv#{@ip_version} rules\n")

      populate_rule_defaults
      generate_all_rules

      deploy_script
      workaround_setup

      apply_rules if @options.restart?
    end

    # deploy workarounds
    workaround_exec
    @node.autostart_service('iptables-persistent') if @node.uses_apt?
  end

  desc 'iptables:status', 'displays iptables rules'
  def status
    @node.messages.add('displaying iptables rules (ipv4)').ok
    @node.messages.add(@node.exec('iptables -L -v -n')[:stdout], :indent => 0)
    @node.messages.add('displaying iptables rules (ipv6)').ok
    @node.messages.add(@node.exec('ip6tables -L -v -n')[:stdout], :indent => 0)
  end

  private

  # install iptables
  def install
    return false unless @node.install_package 'iptables'
    return false unless @node.install_package 'ip6tables' if @node.uses_opkg?
    return false unless @node.install_package 'iptables-persistent' if @node.uses_apt?
    return false unless @node.install_package 'iptables-ipv6' if @node.uses_rpm? and not @node.is_fedora?
    true
  end

  # TODO: remove soon
  # remove rules from old iptables recipe
  def remove_old_scripts
    files = [ '/etc/iptables', '/etc/ip6tables',
              '/etc/network/if-pre-up.d/iptables',
              '/etc/network/if-pre-up.d/ip6tables' ]

    files.each do |file|
      if @node.file_exists?(file, :quiet => true)
        @node.messages.add("found old iptables script '#{file}', removing").warning
        @node.rm(file, :indent => 2)
      end
    end
  end

  # inserts default values to chains, if not given
  # table defaults to filter
  # jump target to ACCEPT
  # protocol to tcp (if port is given)
  # and converts non-arrays to arrays, so .each and .combine won't cause hickups
  def populate_rule_defaults
    @config.values.each do |chain_rules|
      chain_rules.values.each do |rule|
        rule['table'] ||= ['filter']
        rule['jump'] ||= ['ACCEPT']
        rule['protocol'] ||= ['tcp'] if rule['dport'] or rule['sport']
        rule.values_to_array!
      end
    end
  end

  # generates all iptables rules
  def generate_all_rules
    @tables['ipv' + @ip_version.to_s].each do |table, chains|
      @script << "*#{table}\n"
      set_chain_policies table
      generate_rules_for_table table
    end
  end

  # set the chain default policies to DROP/ACCEPT
  # according to whether chain is specified in config file
  # and create custom chains
  def set_chain_policies table

    # build in chains
    @tables['ipv' + @ip_version.to_s][table].each do |chain|
      policy = get_chain_policy table, chain
      @script << ":#{chain.upcase} #{policy} [0:0]\n"
    end

    # custom chains
    @config.each do |chain, chain_rules|
      # filter out build in chains
      next if @tables['ipv' + @ip_version.to_s][table].include? chain.upcase

      # only continue if this chain is used in this table
      chain_used_in_table = false
      chain_rules.each do |name, rule|
        if rule['table'].include? table
          chain_used_in_table = true
          break
        end
      end
      next unless chain_used_in_table

      @script << ":#{chain.upcase} - [0:0]\n"
    end
  end

  # returns DROP if chain and table is specified in config file
  # ACCEPT if not
  def get_chain_policy table, chain
    # only filter table supports DENY target
    return 'ACCEPT' unless table == 'filter'
    return 'ACCEPT' unless @config[chain.downcase]

    @config[chain.downcase].values.each do |rule|
      return 'DROP' if rule['table'].include? table
    end

    return 'ACCEPT'
  end

  # generate iptables rules for table 'table'
  def generate_rules_for_table table
    @config.each do |chain, chain_rules|
      rules = get_rules_for_table chain_rules, table
      next if rules.empty?

      rules.sort.each do |name, rule|
        next unless rule['table'].include? table
        next unless check_ip_version rule

        msg = @node.messages.add("adding rule: #{name}", :indent => 2)
        generate_iptables_string chain, rule
        msg.ok
      end
    end
    @script << "COMMIT\n"
  end

  def get_rules_for_table rules, table
    rules.select { |name, rule| rule['table'].include? table }
  end

  # check if source and destination ip (if given)
  # are valid ips for this ip version
  def check_ip_version rule
    ['source', 'src', 'destination', 'dest', 'to-source'].each do |attr|
      if rule[attr]
        rule[attr].each do |addr|
          return false unless IPAddress(addr).send "ipv#{@ip_version}?"
        end
      end
      # return false if this ip version was manually disabled
      return false unless rule['ip-version'].include? @ip_version if rule['ip-version']
    end
    true
  end

  # generates the iptables string out of a rule
  def generate_iptables_string chain, rule
    parse_rule(rule).each do |r|
      @script << "--append #{chain.upcase} #{r.join ' '}\n"
    end
  end

  # map iptables options
  def parse_rule r
    with_dashes = {}
    result = []

    # map r[key] = value to '--key value'
    r.each do |k, v|
      next if k == 'ip-version' # skip ip-version, since its not iptables option
      next if k == 'table' # iptables-restore takes table argument with *table

      with_dashes[k] = r[k].map do |v|
        value = v.to_s
        if value.start_with? '!', '! '
          # map '--key ! value' to '! --key value'
          value.slice! '!'
          value.lstrip!
          "! --#{k} #{value}"
          else
          "--#{k} #{value}"
        end
      end
    end
    with_dashes.values.each { |a| result = result.combine a }

    sort_rule_options result
  end

  # make sure the options are sorted in a way that works.
  def sort_rule_options rule
    sorted = []
    rule.each do |r|
      # sort rules so it makes sense
      r = r.to_array.sort_by do |x|
        if x.include? '--match'
          -1
          elsif x.include? '--protocol'
          -2
          elsif x.include? '--jump'
          1
          elsif x.include? '--to-port'
          2
          elsif x.include? '--to-destination'
          3
          elsif x.include? '--to-source'
          4
          elsif x.include? '--ttl-set'
          5
          elsif x.include? '--clamp-mss-to-pmtu'
          6
          elsif x.include? '--reject-with'
          7
          else
          0
        end
      end
      sorted.push r
    end

    sorted
  end

  def deploy_script
    target = get_target

    # create directory if not existend
    @node.mkdir(File.dirname(target)) unless @node.dir_exists?(File.dirname(target), :quiet => true)

    @node.write(target, @script, :quiet => true)
    @node.chmod('0600', target)
  end

  def workaround_setup
    # openwrt always needs the workaround
    if @node.uses_opkg?
      @workaround = { 'path' => '/etc/firewall.sh' }

    # iptables-persistent < version 0.5.1 doesn't support ipv6
    # so doing a workaround
    elsif @node.uses_apt? and @ip_version == 6
      unless @node.package_min_version?('iptables-persistent', '0.5.1', :quiet => true)
        @node.messages.add('iptables-persistent too old (< 0.5.1), using workaround for ipv6').warning
        @workaround = { 'path' => '/etc/network/if-pre-up.d/ip6tables' }
      end
    end

    return unless @workaround

    @workaround['script'] ||= "#!/bin/sh\n\n"
    @workaround['script'] << "iptables-restore < #{get_target}\n"
  end

  def workaround_exec
    return unless @workaround

    @node.messages.add('deploying workarounds').warning
    msg = @node.messages.add("deploying script to #{@workaround['path']}", :indent => 2)
    msg.parse_result(@node.write(@workaround['path'], @workaround['script'], :quiet => true))
    @node.chmod('0700', @workaround['path'], :indent => 2)

    if @node.uses_apt?
      # < 0.5.1 uses rules instead of rules.ipver
      # remove old rules script and symlink it to ours
      @node.messages.add('iptables-persistent < 0.5.1 uses rules instead of rules.v4, symlinking',
                         :indent => 2).warning
      @node.rm('/etc/iptables/rules', :indent => 3)
      @node.symlink('/etc/iptables/rules.v4', '/etc/iptables/rules', :indent => 3)

    elsif @node.uses_opkg?
      # overwrite openwrt firewall configuration
      # and only use our script
      @node.write('/etc/config/firewall',
                  "config include\n\toption path /etc/firewall.sh\n", :indent => 2)

      # disable openwrt firewall hotplug scripts
      msg = @node.messages.add('disabling firewall hotplug scripts in /etc/hotplug.d/firewall', :indent => 2)
      msg.parse_result(@node.exec('chmod -x /etc/hotplug.d/firewall/*')[:exit_code])
    end
  end

  # apply newly pushed rules
  def apply_rules
    msg = @node.messages.add("applying ipv#{@ip_version} rules")
    msg.parse_result(@node.exec("#{get_cmd}-restore < #{get_target}")[:exit_code])
  end

  # set the target file depending on distribution
  def get_target
    if @node.uses_apt?
      target = "/etc/iptables/rules.v#{@ip_version}"
    elsif @node.uses_rpm?
      target = "/etc/sysconfig/#{get_cmd}"
    elsif @node.uses_emerge?
      target = "/var/lib/#{get_cmd}/rules-save"
    elsif @node.uses_pacman?
      target = "/etc/iptables/#{get_cmd}.rules"
    else
      target = "/etc/#{get_cmd}-rules.ipt"
    end

    target
  end

  def get_cmd
    return 'iptables' if @ip_version == 4
    return 'ip6tables' if @ip_version == 6
  end
end
