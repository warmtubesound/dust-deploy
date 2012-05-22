class Limits < Recipe

  desc 'limit:deploy', 'maintains /etc/security/limits.d'
  def deploy
    # valid values
    types = [ 'hard', 'soft' ]
    items = [ 'core', 'data', 'fsize', 'memlock', 'nofile', 'rss', 'stack', 'cpu',
              'nproc', 'as', 'maxlogins', 'maxsyslogins', 'priority', 'locks',
              'sigpending', 'msgqueue', 'nice', 'rtprio', 'chroot' ]

    unless @node.dir_exists? '/etc/security/limits.d'
      return @node.messages.add('your system does not support /etc/security/limits.d').failed
    end

    clean

    @config.each do |name, rules|
      limits_conf = ''
      @node.messages.add("assembling system limits according to rule '#{name}'\n")
      rules.to_array.each do |rule|

        # check if entry is valid
        unless rule['domain']
          @node.messages.add("domain cannot be empty, skipping", :indent => 2).failed
          next
        end

        unless rule['value']
          @node.messages.add("value cannot be empty, skipping", :indent => 2).failed
          next
        end

        unless items.include? rule['item']
          @node.messages.add("'#{rule['item']}' is not a valid item, skipping. valid items: #{items.join(',')}", :indent => 2).failed
          next
        end

        unless types.include? rule['type']
          @node.messages.add("'#{rule['type']}' is not a valid type, skipping. valid types: #{types.join(',')}", :indent => 2).failed
          next
        end

        # assemble rule
        line = "#{rule['domain']}\t#{rule['type']}\t#{rule['item']}\t#{rule['value']}\n"
        @node.messages.add("adding '#{line.chomp}'", :indent => 2).ok
        limits_conf << line
      end

      # deploy rule file
      msg = @node.messages.add("deploying limits to /etc/security/limits.d/#{name}")
      msg.parse_result(@node.write("/etc/security/limits.d/#{name}", limits_conf, :quiet => true))
    end
  end


  private

  # removes all files in /etc/security/limits.d
  def clean
    msg = @node.messages.add('cleaning all files from /etc/security/limits.d')
    msg.parse_result(@node.rm('/etc/security/limits.d/*', :quiet => true))
  end
end
