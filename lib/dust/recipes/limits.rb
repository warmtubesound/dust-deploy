class Limits < Recipe

  desc 'limit:deploy', 'maintains /etc/security/limits.d'
  def deploy
    # valid values
    types = [ 'hard', 'soft' ]
    items = [ 'core', 'data', 'fsize', 'memlock', 'nofile', 'rss', 'stack', 'cpu',
              'nproc', 'as', 'maxlogins', 'maxsyslogins', 'priority', 'locks',
              'sigpending', 'msgqueue', 'nice', 'rtprio', 'chroot' ]

    unless @node.dir_exists? '/etc/security/limits.d'
      return ::Dust.print_failed 'your system does not support /etc/security/limits.d'
    end
    puts

    @config.each do |name, rules|
      limits_conf = ''
      ::Dust.print_msg "assembling system limits according to rule '#{name}'\n"
      rules.to_array.each do |rule|

        # check if entry is valid
        unless rule['domain']
          ::Dust.print_failed "domain cannot be empty, skipping", :indent => 2
          next
        end

        unless rule['value']
          ::Dust.print_failed "value cannot be empty, skipping", :indent => 2
          next
        end

        unless items.include? rule['item']
          ::Dust.print_failed "'#{rule['item']}' is not a valid item, skipping. valid items: #{items.join(',')}", :indent => 2
          next
        end

        unless types.include? rule['type']
          ::Dust.print_failed "'#{rule['type']}' is not a valid type, skipping. valid types: #{types.join(',')}", :indent => 2
          next
        end

        # assemble rule
        line = "#{rule['domain']}\t#{rule['type']}\t#{rule['item']}\t#{rule['value']}\n"
        ::Dust.print_ok "adding '#{line.chomp}'", :indent => 2
        limits_conf << line
      end

      # deploy rule file
      ::Dust.print_msg "deploying limits to /etc/security/limits.d/#{name}"
      ::Dust.print_result @node.write("/etc/security/limits.d/#{name}", limits_conf, :quiet => true)
      puts
    end
  end

end
