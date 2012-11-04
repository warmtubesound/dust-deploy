require 'dust/server/ssh'
require 'dust/server/osdetect'

module Dust
  class Server
    # checks if one of the packages is installed
    def package_installed?(packages, options={})
      options = default_options.merge(options)

      packages = [ packages ] if packages.is_a?(String)

      msg = messages.add("checking if #{packages.join(' or ')} is installed", options)

      packages.each do |package|
        if uses_apt?
          return msg.ok if exec("dpkg -l #{package} |grep '^ii'")[:exit_code] == 0
        elsif uses_emerge?
          return msg.ok unless exec("qlist -I #{package}")[:stdout].empty?
        elsif uses_rpm?
          return msg.ok if exec("rpm -q #{package}")[:exit_code] == 0
        elsif uses_pacman?
          return msg.ok if exec("pacman -Q #{package}")[:exit_code] == 0
        elsif uses_opkg?
          return msg.ok unless exec("opkg status #{package}")[:stdout].empty?
        end
      end

      msg.failed
    end

    def install_package(package, options={})
      options = default_options.merge(options)
      options[:env] ||= ''

      if package_installed?(package, :quiet => true)
        return messages.add("package #{package} already installed", options).ok
      end

      # if package is an url, download and install the package file
      if package =~ /^(http:\/\/|https:\/\/|ftp:\/\/)/
        if uses_apt?
          messages.add("installing #{package}\n", options)
          return false unless install_package('wget')

          msg = messages.add('downloading package', options.merge(:indent => options[:indent] + 1))

          # creating temporary file
          tmpfile = mktemp
          return msg.failed('could not create temporary file') unless tmpfile

          msg.parse_result(exec("wget #{package} -O #{tmpfile}")[:exit_code])

          msg = messages.add('installing package', options.merge(:indent => options[:indent] + 1))
          ret = msg.parse_result(exec("dpkg -i #{tmpfile}")[:exit_code])

          msg = messages.add('deleting downloaded file', options.merge(:indent => options[:indent] + 1))
          msg.parse_result(rm(tmpfile, :quiet => true))

          return ret

        elsif uses_rpm?
          msg = messages.add("installing #{package}", options)
          return msg.parse_result(exec("rpm -U #{package}")[:exit_code])

        else
          return msg.failed("\ninstalling packages from url not yet supported " +
                            "for your distribution. feel free to contribute!").failed
        end

      # package is not an url, use package manager
      else
        msg = messages.add("installing #{package}", options)

        if uses_apt?
          exec "DEBIAN_FRONTEND=noninteractive aptitude install -y #{package}"
        elsif uses_emerge?
          exec "#{options[:env]} emerge #{package}"
        elsif uses_rpm?
          exec "yum install -y #{package}"
        elsif uses_pacman?
          exec "echo y |pacman -S #{package}"
        elsif uses_opkg?
          exec "opkg install #{package}"
        else
          return msg.failed("\ninstall_package only supports apt, emerge and yum systems at the moment")
        end

        # check if package actually was installed
        return msg.parse_result(package_installed?(package, :quiet => true))
      end
    end

    # check if installed package is at least version min_version
    def package_min_version?(package, min_version, options={})
      msg = messages.add("checking if #{package} is at least version #{min_version}", options)
      return msg.failed unless package_installed?(package, :quiet => true)

      if uses_apt?
        v = exec("dpkg --list |grep #{package}")[:stdout].chomp
      elsif uses_rpm?
        v = exec("rpm -q #{package}")[:stdout].chomp
      elsif uses_pacman?
        v = exec("pacman -Q #{package}")[:stdout].chomp
      else
        return msg.failed('os not supported')
      end

      # convert version numbers to arrays
      current_version = v.to_s.split(/[-. ]/ ).select {|j| j =~ /^[0-9]+$/ }
      min_version = min_version.to_s.split(/[-. ]/ ).select {|j| j =~ /^[0-9]+$/ }

      # compare
      min_version.each_with_index do |i, pos|
        break unless current_version[pos]
        return msg.failed if i.to_i < current_version[pos].to_i
      end

      msg.ok
    end

    def remove_package(package, options={})
      options = default_options.merge(options)

      unless package_installed?(package, :quiet => true)
        return messages.add("package #{package} not installed", options).ok
      end

      msg = messages.add("removing #{package}", options)
      if uses_apt?
        msg.parse_result(exec("DEBIAN_FRONTEND=noninteractive aptitude purge -y #{package}")[:exit_code])
      elsif uses_emerge?
        msg.parse_result(exec("emerge --unmerge #{package}")[:exit_code])
      elsif uses_rpm?
        msg.parse_result(exec("yum erase -y #{package}")[:exit_code])
      elsif uses_pacman?
        msg.parse_result(exec("echo y |pacman -R #{package}")[:exit_code])
      elsif uses_opkg?
        msg.parse_result(exec("opkg remove #{package}")[:exit_code])
      else
        msg.failed
      end
    end

    def update_repos(options={})
      options = default_options.merge(options)

      msg = messages.add('updating system repositories', options)

      if uses_apt?
        ret = exec('aptitude update', options)
      elsif uses_emerge?
        ret = exec('emerge --sync', options)
      elsif uses_rpm?
        ret = exec('yum check-update', options)

        # yum returns != 0 if packages that need to be updated are found
        # we don't want that this is producing an error
        ret[:exit_code] = 0 if ret[:exit_code] == 100
      elsif uses_pacman?
        ret = exec('pacman -Sy', options)
      elsif uses_opkg?
        ret =  exec('opkg update', options)
      else
        return msg.failed
      end

      unless options[:live]
        msg.parse_result(ret[:exit_code])
      end

      ret[:exit_code]
    end

    def system_update(options={})
      options = default_options.merge(:live => true).merge(options)

      update_repos

      msg = messages.add('installing system updates', options)

      if uses_apt?
        ret = exec('DEBIAN_FRONTEND=noninteractive aptitude full-upgrade -y', options)
      elsif uses_emerge?
        ret = exec('emerge -uND @world', options)
      elsif uses_rpm?
        ret = exec('yum upgrade -y', options)
      elsif uses_pacman?
        # pacman has no --yes option that i know of, so echoing y
        ret = exec('echo y |pacman -Su', options)
      elsif uses_opkg?
        # upgrading openwrt is very experimental, and should not used normally
        ret = exec('opkg upgrade $(echo $(opkg list-upgradable |cut -d' ' -f1 |grep -v Multiple))', options)
      else
        msg.failed('system not (yet) supported')
        return false
      end

      unless options[:live]
        msg.parse_result(ret[:exit_code])
      end

      ret[:exit_code]
    end
  end
end
