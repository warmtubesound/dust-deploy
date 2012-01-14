require 'ipaddress'

class Iptables < Thor
  
  desc 'iptables:deploy', 'configures iptables firewall'
  def deploy node, rules, options
    template_path = "./templates/#{ File.basename(__FILE__).chomp( File.extname(__FILE__) ) }"
    @node = node
    @rules = rules
    @options = options

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
    
    [4, 6].each do |v|
      @script = '' 
      @ip_version = v
      
      ::Dust.print_msg "generating ipv#{@ip_version} rules\n"

      clear_all_tables
      populate_rule_defaults
      generate_all_rules
        
      deploy_script
      apply_rules
      
      puts
    end
  end


  private

  # install iptables
  def install
    return false unless @node.install_package 'iptables'
    return false unless @node.install_package 'iptables-ipv6' if @node.uses_rpm?
    true
  end
  
  # deletes all rules/chains
  def clear_all_tables
    return if @node.uses_rpm?
    
    # clear all rules
    @tables['ipv' + @ip_version.to_s].keys.each { |table| @script.concat "--flush --table #{table}\n" }
    
    # delete all custom chains
    @script.concat "--delete-chain \n" unless @node.uses_rpm?
  end
  
  # inserts default values to chains, if not given
  # table defaults to filter
  # jump target to ACCEPT
  # protocol to tcp (if port is given)
  # and converts non-arrays to arrays, so .each and .combine won't cause hickups
  def populate_rule_defaults
    @rules.values.each do |chain_rules|
      chain_rules.values.each do |rule|
        rule['table'] ||= ['filter']
        rule['jump'] ||= ['ACCEPT']
        rule['protocol'] ||= ['tcp'] if rule['dport'] or rule['sport']
        rule.each { |k, v| rule[k] = [ rule[k] ] unless rule[k].is_a? Array }
      end
    end
  end
  
  # generates all iptables rules
  def generate_all_rules
    @tables['ipv' + @ip_version.to_s].each do |table, chains|
      @script.concat "*#{table}\n" if @node.uses_rpm? 
      set_chain_policies table
      generate_rules_for_table table
    end
  end

  # set the chain default policies to DROP/ACCEPT
  # according to whether chain is specified in config file
  def set_chain_policies table
    ::Dust.print_msg "#{::Dust.pink}#{table}#{Dust.none} table\n", :indent => 2
    ::Dust.print_msg "setting default policies\n", :indent => 3
    
    @tables['ipv' + @ip_version.to_s][table].each do |chain|
      policy = get_chain_policy table, chain
      ::Dust.print_msg "#{table}/#{chain} -> #{policy}", :indent => 4

      if @node.uses_rpm?
        @script.concat ":#{chain.upcase} #{policy} [0:0]\n"
      else
        @script.concat "--table #{table} --policy #{chain.upcase} #{policy}\n"
      end
      
      ::Dust.print_ok
    end
  end

  # returns DROP if chain and table is specified in config file
  # ACCEPT if not
  def get_chain_policy table, chain
    return 'ACCEPT' unless @rules[chain.downcase]

    @rules[chain.downcase].values.each do |rule|
      return 'DROP' if rule['table'].include? table
    end

    return 'ACCEPT'
  end

  # generate iptables rules for table 'table'
  def generate_rules_for_table table
    @rules.each do |chain, chain_rules|
      rules = get_rules_for_table chain_rules, table
      next if rules.empty?
      
      ::Dust.print_msg "#{::Dust.pink}#{chain}#{::Dust.none} rules\n", :indent => 3
      
      rules.sort.each do |name, rule|
        next unless rule['table'].include? table
        next unless check_ip_version rule
        
        ::Dust.print_msg "#{name}\n", :indent => 4
        generate_iptables_string chain, rule
      end
    end
    @script.concat "COMMIT\n" if @node.uses_rpm?
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
      ::Dust.print_msg "#{::Dust.grey}#{r.join ' '}#{::Dust.none}\n", :indent => 5
      @script.concat "--append #{chain.upcase} #{r.join ' '}\n"
    end
  end

  # map iptables options
  def parse_rule r
    with_dashes = {}
    result = []
    
    # map r[key] = value to '--key value'
    r.each do |k, v|
      next if k == 'ip-version' # skip ip-version, since its not iptables option
      next if k == 'table' if @node.uses_rpm? # rpm-firewall takes table argument with *table
      
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
      r = r.sort_by do |x|
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
    
    prepend_cmd
    prepend_header    
    
    @node.write target, @script, :quiet => true

    if @node.uses_rpm?
      @node.chmod '600', target
    else
      @node.chmod '700', target      
    end
  end

  # put dust comment at the beginning of the file
  def prepend_header
    @script.insert 0, "#!/bin/sh\n" unless @node.uses_rpm?
    @script.insert 0, "# automatically generated by dust\n\n"
  end
  
  # prepend iptables command on non-centos-like machines
  def prepend_cmd
    @script = @script.map { |s| "#{cmd} #{s}" }.to_s unless @node.uses_rpm?
  end
  
  # apply newly pushed rules
  def apply_rules
    if @options.restart?
      ::Dust.print_msg "applying ipv#{@ip_version} rules"
      
      if @node.uses_rpm?
        ::Dust.print_result @node.exec("/etc/init.d/#{cmd} restart")[:exit_code]

      else
        ret = @node.exec get_target
        ::Dust.print_result( (ret[:exit_code] == 0 and ret[:stdout].empty? and ret[:stderr].empty?) )
      end
    end

    # on gentoo, rules have to be saved using the init script,
    # otherwise they won't get re-applied on next startup
    if @node.uses_emerge?
      ::Dust.print_msg "saving ipv#{@ip_version} rules"
      ::Dust.print_result @node.exec("/etc/init.d/#{cmd} save")[:exit_code]
    end
  end

  # set the target file depending on distribution
  def get_target
    target = "/etc/#{cmd}"    
    target = "/etc/network/if-pre-up.d/#{cmd}" if @node.uses_apt?
    target = "/etc/sysconfig/#{cmd}" if @node.uses_rpm?
    target
  end
  
  def cmd
    return 'iptables' if @ip_version == 4
    return 'ip6tables' if @ip_version == 6
  end

end

