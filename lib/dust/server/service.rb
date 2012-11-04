require 'dust/server/ssh'

module Dust
  class Server
    def autostart_service(service, options={})
      options = default_options.merge(options)

      msg = messages.add("autostart #{service} on boot", options)

      if uses_rpm?
        if file_exists? '/bin/systemctl', :quiet => true
          msg.parse_result(exec("systemctl enable #{service}.service")[:exit_code])
        else
          msg.parse_result(exec("chkconfig #{service} on")[:exit_code])
        end

      elsif uses_apt?
        msg.parse_result(exec("update-rc.d #{service} defaults")[:exit_code])

      elsif uses_emerge?
        msg.parse_result(exec("rc-update add #{service} default")[:exit_code])

      # archlinux needs his autostart daemons in /etc/rc.conf, in the DAEMONS line
      #elsif uses_pacman?

      else
        msg.failed
      end
    end

    # invoke 'command' on the service (e.g. @node.service 'postgresql', 'restart')
    def service(service, command, options={})
      options = default_options.merge(options)

      return messages.add("service: '#{service}' unknown", options).failed unless service.is_a? String

      # try systemd, then upstart, then sysvconfig, then rc.d, then initscript
      if file_exists? '/bin/systemctl', :quiet => true
        msg = messages.add("#{command}ing #{service} (via systemd)", options)
        ret = exec("systemctl #{command} #{service}.service")

      elsif file_exists? "/etc/init/#{service}", :quiet => true
        msg = messages.add("#{command}ing #{service} (via upstart)", options)
        ret = exec("#{command} #{service}")

      elsif file_exists? '/sbin/service', :quiet => true or file_exists? '/usr/sbin/service', :quiet => true
        msg = messages.add("#{command}ing #{service} (via sysvconfig)", options)
        ret = exec("service #{service} #{command}")

      elsif file_exists? '/usr/sbin/rc.d', :quiet => true
        msg = messages.add("#{command}ing #{service} (via rc.d)", options)
        ret = exec("rc.d #{command} #{service}")

      else
        msg = messages.add("#{command}ing #{service} (via initscript)", options)
        ret = exec("/etc/init.d/#{service} #{command}")
      end

      msg.parse_result(ret[:exit_code])
      ret
    end

    def restart_service(service, options={})
      options = default_options.merge(options)

      service(service, 'restart', options)
    end

    def reload_service(service, options={})
      options = default_options.merge(options)

      service(service, 'reload', options)
    end

    def print_service_status(service, options={})
      options = default_options.merge(:indent => 0).merge(options)
      ret = service(service, 'status', options)
      messages.add('', options).print_output(ret)
      ret
    end
  end
end
