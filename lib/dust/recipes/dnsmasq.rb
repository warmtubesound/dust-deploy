class Dnsmasq < Recipe
  desc 'dnsmasq:deploy', 'installs and configures dnsmasq'
  def deploy
    return unless @node.install_package 'dnsmasq'

    dnsmasq_conf = ''
    @config.each do |key, values|

      # some settings can be specified multiple times
      # this is represented in the node.yaml as arrays e.g.
      # server: [ nameserver1, '/yourdomain/yournameserver/' ]
      # this will be translated to
      # server=nameserver1
      # server=/yourdomain/yournameserver/
      Array(values).each do |value|

        # dnsmasq has some settings which are just set without a value
        # in the node.yaml, this has to be specified using e.g.
        # no-resolv: true
        # this will be translated by this script to
        # no-resolv
        # we're also skipping settings that are set to false
        next if value.is_a? FalseClass

        if value.is_a? TrueClass
          dnsmasq_conf << "#{key}\n"

        # all other settings have key=value pairs
        else
          dnsmasq_conf << "#{key}=#{value}\n"
        end

      end
    end

    @node.write '/etc/dnsmasq.conf', dnsmasq_conf
    @node.restart_service 'dnsmasq' if @options.restart
  end
end
