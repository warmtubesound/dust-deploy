require 'dust/server/ssh'

module Dust
  class Server
    # determining the system packet manager has to be done without facter
    # because it's used to find out whether facter is installed / install facter
    def uses_apt?(options={})
      options = default_options(:quiet => true).merge(options)

      return @uses_apt if defined?(@uses_apt)
      msg = messages.add('determining whether node uses apt', options)
      @uses_apt = msg.parse_result(exec('test -e /etc/debian_version')[:exit_code])
    end

    def uses_rpm?(options={})
      options = default_options(:quiet => true).merge(options)

      return @uses_rpm if defined?(@uses_rpm)
      msg = messages.add('determining whether node uses rpm', options)
      @uses_rpm = msg.parse_result(exec('test -e /etc/redhat-release')[:exit_code])
    end

    def uses_emerge?(options={})
      options = default_options(:quiet => true).merge(options)

      return @uses_emerge if defined?(@uses_emerge)
      msg = messages.add('determining whether node uses emerge', options)
      @uses_emerge = msg.parse_result(exec('test -e /etc/gentoo-release')[:exit_code])
    end

    def uses_pacman?(options={})
      options = default_options(:quiet => true).merge(options)

      return @uses_pacman if defined?(@uses_pacman)
      msg = messages.add('determining whether node uses pacman', options)
      @uses_pacman = msg.parse_result(exec('test -e /etc/arch-release')[:exit_code])
    end

    def uses_opkg?(options={})
      options = default_options(:quiet => true).merge(options)

      return @uses_opkg if defined?(@uses_opkg)
      msg = messages.add('determining whether node uses opkg', options)
      @uses_opkg = msg.parse_result(exec('test -e /etc/opkg.conf')[:exit_code])
    end

    def is_os?(os_list, options={})
      options = default_options(:quiet => true).merge(options)

      msg = messages.add("checking if this machine runs #{os_list.join(' or ')}", options)
      return msg.failed unless collect_facts options

      os_list.each do |os|
        if @node['operatingsystem'].downcase == os.downcase
          return msg.ok
        end
      end

      msg.failed
      false
    end

    def is_debian?(options={})
      options = default_options(:quiet => true).merge(options)

      return false unless uses_apt?
      is_os?(['debian'], options)
    end

    def is_ubuntu?(options={})
      options = default_options(:quiet => true).merge(options)

      return false unless uses_apt?
      is_os?(['ubuntu'], options)
    end

    def is_gentoo?(options={})
      options = default_options(:quiet => true).merge(options)

      return false unless uses_emerge?
      is_os?(['gentoo'], options)
    end

    def is_centos?(options={})
      options = default_options(:quiet => true).merge(options)

      return false unless uses_rpm?
      is_os?(['centos'], options)
    end

    def is_scientific?(options={})
      options = default_options(:quiet => true).merge(options)

      return false unless uses_rpm?
      is_os?(['scientific'], options)
    end

    def is_fedora?(options={})
      options = default_options(:quiet => true).merge(options)

      return false unless uses_rpm?
      is_os?(['fedora'], options)
    end

    def is_arch?(options={})
      options = default_options(:quiet => true).merge(options)

      return false unless uses_pacman?
      is_os?(['archlinux'], options)
    end
  end
end
