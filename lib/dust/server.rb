require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'net/ssh/proxy/socks5'
require 'erb'
require 'tempfile'
require 'colorize'

module Dust
  class Server
    attr_reader :ssh, :messages

    def default_options options = {}
      { :quiet => false, :indent => 1 }.merge options
    end

    def initialize node
      @node = node
      @node['user'] ||= 'root'
      @node['port'] ||= 22
      @node['password'] ||= ''
      @node['sudo'] ||= false

      @messages = Messages.new
    end

    def connect
      messages.print_hostname_header(@node['hostname']) unless $parallel

      begin
        # connect to proxy if given
        if @node['proxy']
          host, port = @node['proxy'].split ':'
          proxy = Net::SSH::Proxy::SOCKS5.new(host, port)
        else
          proxy = nil
        end

        @ssh = Net::SSH.start @node['fqdn'], @node['user'],
                              { :password => @node['password'],
                                :port => @node['port'],
                                :proxy => proxy }
      rescue Exception
        error_message = "coudln't connect to #{@node['fqdn']}"
        error_message << " (via socks5 proxy #{@node['proxy']})" if proxy
        messages.add(error_message, :indent => 0).failed
        return false
      end

      true
    end

    def disconnect
      @ssh.close
    end

    def exec command, options={:live => false, :as_user => false}
      sudo_authenticated = false
      stdout = ''
      stderr = ''
      exit_code = nil
      exit_signal = nil

      # prepend a newline, if output is live
      messages.add("\n", :indent => 0) if options[:live]

      @ssh.open_channel do |channel|

        # if :as_user => user is given, execute as user (be aware of ' usage)
        command = "su #{options[:as_user]} -l -c '#{command}'" if options[:as_user]

        # request a terminal (sudo needs it)
        # and prepend "sudo"
        # command is wrapped in ", escapes " in the command string
        # and then executed using "sh -c", so that
        # the use of > < && || | and ; doesn't screw things up
        if @node['sudo']
          channel.request_pty
          command = "sudo -k -- sh -c \"#{command.gsub('"','\\"')}\""
        end

        channel.exec command do |ch, success|
          abort "FAILED: couldn't execute command (ssh.channel.exec)" unless success

          channel.on_data do |ch, data|

            # only send password if sudo mode is enabled,
            # and only send password once in a session (trying to prevent attacks reading out the password)
            if @node['sudo'] and not sudo_authenticated
              # skip everything till password is prompted
              next unless data =~ /^\[sudo\] password for #{@node['user']}/
              channel.send_data "#{@node['password']}\n"
              sudo_authenticated = true
            else
              stdout += data
              messages.add(data.green, :indent => 0) if options[:live] and not data.empty?
            end
          end

          channel.on_extended_data do |ch, type, data|
            stderr += data
            messages.add(data.red, :indent => 0) if options[:live] and not data.empty?
          end

          channel.on_request('exit-status') { |ch, data| exit_code = data.read_long }
          channel.on_request('exit-signal') { |ch, data| exit_signal = data.read_long }
        end
      end

      @ssh.loop

      # sudo usage provokes a heading newline that's unwanted.
      stdout.sub! /^(\r\n|\n|\r)/, '' if @node['sudo']

      { :stdout => stdout, :stderr => stderr, :exit_code => exit_code, :exit_signal => exit_signal }
    end

    def write destination, content, options = {}
      options = default_options.merge options

      msg = messages.add("deploying #{File.basename destination}", options)

      f = Tempfile.new 'dust-write'
      f.print content
      f.close

      ret = msg.parse_result(scp(f.path, destination, :quiet => true))
      f.unlink

      ret
    end

    def append destination, newcontent, options = {}
      options = default_options.merge options

      msg = messages.add("appending to #{File.basename destination}", options)

      content = exec("cat #{destination}")[:stdout]
      content.concat newcontent

      msg.parse_result(write(destination, content, :quiet => true))
    end

    def scp source, destination, options = {}
      options = default_options.merge options

      # make sure scp is installed on client
      install_package 'openssh-clients', :quiet => true if uses_rpm?

      msg = messages.add("deploying #{File.basename source}", options)

      # check if destination is a directory
      is_dir = dir_exists?(destination, :quiet => true)

      # save permissions if the file already exists
      ret = exec "stat -c %a:%u:%g #{destination}"
      if ret[:exit_code] == 0 and not is_dir
        permissions, user, group = ret[:stdout].chomp.split ':'
      else
        # files = 644, dirs = 755
        permissions = 'ug-x,o-wx,u=rwX,g=rX,o=rX'
      end

      # if in sudo mode, copy file to temporary place, then move using sudo
      if @node['sudo']
        tmpfile = mktemp
        return msg.failed('could not create temporary file (needed for sudo)') unless tmpfile

        # allow user to write file without sudo (for scp)
        # then change file back to root, and copy to the destination
        chown @node['user'], tmpfile, :quiet => true
        @ssh.scp.upload! source, tmpfile
        chown 'root', tmpfile, :quiet => true

        # if destination is a directory, append real filename
        destination = "#{destination}/#{File.basename(source)}" if is_dir

        # move the file from the temporary location to where it actually belongs
        msg.parse_result(exec("mv -f #{tmpfile} #{destination}")[:exit_code])

      else
        @ssh.scp.upload! source, destination
        msg.ok
      end

      # set file permissions
      chown "#{user}:#{group}", destination, :quiet => true if user and group
      chmod permissions, destination, :quiet => true

      restorecon destination, options # restore SELinux labels
    end

    # download a file (sudo not yet supported)
    def download source, destination, options = {}
      options = default_options.merge options

      # make sure scp is installed on client
      install_package 'openssh-clients', :quiet => true if uses_rpm?

      msg = messages.add("downloading #{File.basename source}", options)
      msg.parse_result(@ssh.scp.download!(source, destination))
    end

    def symlink source, destination, options = {}
      options = default_options.merge options

      msg = messages.add("symlinking #{File.basename source} to '#{destination}'", options)
      ret = msg.parse_result(exec("ln -s #{source} #{destination}")[:exit_code])
      restorecon destination, options # restore SELinux labels
      ret
    end

    def chmod mode, file, options = {}
      options = default_options.merge options

      msg = messages.add("setting mode of #{File.basename file} to #{mode}", options)
      msg.parse_result(exec("chmod -R #{mode} #{file}")[:exit_code])
    end

    def chown user, file, options = {}
      options = default_options.merge options

      msg = messages.add("setting owner of #{File.basename file} to #{user}", options)
      msg.parse_result(exec("chown -R #{user} #{file}")[:exit_code])
    end

    def rm file, options = {}
      options = default_options.merge options

      msg = messages.add("deleting #{file}", options)
      msg.parse_result(exec("rm -rf #{file}")[:exit_code])
    end

    def cp source, destination, options = {}
      options = default_options.merge options

      # get rid of overly careful aliases
      exec 'unalias -a'

      msg = messages.add("copying #{source} to #{destination}", options)
      msg.parse_result(exec("cp -a #{source} #{destination}")[:exit_code])
    end

    def mv source, destination, options = {}
      options = default_options.merge options

      # get rid of overly careful aliases
      exec 'unalias -a'

      msg = messages.add("moving #{source} to #{destination}", options)
      msg.parse_result(exec("mv #{source} #{destination}")[:exit_code])
    end

    def mkdir dir, options = {}
      options = default_options.merge options

      return true if dir_exists? dir, :quiet => true

      msg = messages.add("creating directory #{dir}", options)
      ret = msg.parse_result(exec("mkdir -p #{dir}")[:exit_code])
      restorecon dir, options # restore SELinux labels
      ret
    end

    # check if restorecon (selinux) is available
    # if so, run it on "path" recursively
    def restorecon path, options = {}
      options = default_options.merge options

      # if restorecon is not installed, just return true
      ret = exec 'which restorecon'
      return true unless ret[:exit_code] == 0

      msg = messages.add("restoring selinux labels for #{path}", options)
      msg.parse_result(exec("#{ret[:stdout].chomp} -R #{path}")[:exit_code])
    end

    def get_system_users options = {}
      options = default_options.merge options

      msg = messages.add("getting all system users", options)
      ret = exec 'getent passwd |cut -d: -f1'
      msg.parse_result(ret[:exit_code])

      users = []
      ret[:stdout].each do |user|
        users.push user.chomp
      end
      users
    end

    # checks if one of the packages is installed
    def package_installed? packages, options = {}
      options = default_options.merge options

      packages = [ packages ] if packages.is_a? String

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

    def install_package package, options = {}
      options = default_options.merge options
      options[:env] ||= ''

      if package_installed? package, :quiet => true
        return messages.add("package #{package} already installed", options).ok
      end

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
        return msg.failed("install_package only supports apt, emerge and yum systems at the moment")
      end

      # check if package actually was installed
      msg.parse_result(package_installed?(package, :quiet => true))
    end

    # check if installed package is at least version min_version
    def package_min_version?(package, min_version, options = {})
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

    def remove_package package, options = {}
      options = default_options.merge options

      unless package_installed? package, :quiet => true
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

    def update_repos options = {}
      options = default_options.merge options

      msg = messages.add('updating system repositories', options)

      if uses_apt?
        ret = exec 'aptitude update', options
      elsif uses_emerge?
        ret = exec 'emerge --sync', options
      elsif uses_rpm?
        ret = exec 'yum check-update', options

        # yum returns != 0 if packages that need to be updated are found
        # we don't want that this is producing an error
        ret[:exit_code] = 0 if ret[:exit_code] == 100
      elsif uses_pacman?
        ret = exec 'pacman -Sy', options
      elsif uses_opkg?
        ret =  exec 'opkg update', options
      else
        return msg.failed
      end

      unless options[:live]
        msg.parse_result(ret[:exit_code])
      end

      ret[:exit_code]
    end

    def system_update options = {}
      options = default_options.merge(:live => true).merge(options)

      update_repos

      msg = messages.add('installing system updates', options)

      if uses_apt?
        ret = exec 'DEBIAN_FRONTEND=noninteractive aptitude full-upgrade -y', options
      elsif uses_emerge?
        ret = exec 'emerge -uND @world', options
      elsif uses_rpm?
        ret = exec 'yum upgrade -y', options
      elsif uses_pacman?
        # pacman has no --yes option that i know of, so echoing y
        ret = exec 'echo y |pacman -Su', options
      elsif uses_opkg?
        # upgrading openwrt is very experimental, and should not used normally
        ret = exec 'opkg upgrade $(echo $(opkg list-upgradable |cut -d' ' -f1 |grep -v Multiple))', options
      else
        msg.failed('system not (yet) supported')
        return false
      end

      unless options[:live]
        msg.parse_result(ret[:exit_code])
      end

      ret[:exit_code]
    end

    # determining the system packet manager has to be done without facter
    # because it's used to find out whether facter is installed / install facter
    def uses_apt? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_apt if defined? @uses_apt
      msg = messages.add('determining whether node uses apt', options)
      @uses_apt = msg.parse_result(exec('test -e /etc/debian_version')[:exit_code])
    end

    def uses_rpm? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_rpm if defined? @uses_rpm
      msg = messages.add('determining whether node uses rpm', options)
      @uses_rpm = msg.parse_result(exec('test -e /etc/redhat-release')[:exit_code])
    end

    def uses_emerge? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_emerge if defined? @uses_emerge
      msg = messages.add('determining whether node uses emerge', options)
      @uses_emerge = msg.parse_result(exec('test -e /etc/gentoo-release')[:exit_code])
    end

    def uses_pacman? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_pacman if defined? @uses_pacman
      msg = messages.add('determining whether node uses pacman', options)
      @uses_pacman = msg.parse_result(exec('test -e /etc/arch-release')[:exit_code])
    end

    def uses_opkg? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_opkg if defined? @uses_opkg
      msg = messages.add('determining whether node uses opkg', options)
      @uses_opkg = msg.parse_result(exec('test -e /etc/opkg.conf')[:exit_code])
    end

    def is_os? os_list, options = {}
      options = default_options(:quiet => true).merge options

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

    def is_debian? options = {}
      options = default_options(:quiet => true).merge options

      return false unless uses_apt?
      is_os? ['debian'], options
    end

    def is_ubuntu? options = {}
      options = default_options(:quiet => true).merge options

      return false unless uses_apt?
      is_os? ['ubuntu'], options
    end

    def is_gentoo? options = {}
      options = default_options(:quiet => true).merge options

      return false unless uses_emerge?
      is_os? ['gentoo'], options
    end

    def is_centos? options = {}
      options = default_options(:quiet => true).merge options

      return false unless uses_rpm?
      is_os? ['centos'], options
    end

    def is_scientific? options = {}
      options = default_options(:quiet => true).merge options

      return false unless uses_rpm?
      is_os? ['scientific'], options
    end

    def is_fedora? options = {}
      options = default_options(:quiet => true).merge options

      return false unless uses_rpm?
      is_os? ['fedora'], options
    end

    def is_arch? options = {}
      options = default_options(:quiet => true).merge options

      return false unless uses_pacman?
      is_os? ['archlinux'], options
    end

    def is_executable? file, options = {}
      options = default_options.merge options

      msg = messages.add("checking if file #{file} exists and is executeable", options)
      msg.parse_result(exec("test -x $(which #{file})")[:exit_code])
    end

    def file_exists? file, options = {}
      options = default_options.merge options

      msg = messages.add("checking if file #{file} exists", options)

      # don't treat directories as files
      return msg.failed if dir_exists?(file, :quiet => true)

      msg.parse_result(exec("test -e #{file}")[:exit_code])
    end

    def dir_exists? dir, options = {}
      options = default_options.merge options

      msg = messages.add("checking if directory #{dir} exists", options)
      msg.parse_result(exec("test -d #{dir}")[:exit_code])
    end

    def autostart_service service, options = {}
      options = default_options.merge options

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
    def service service, command, options = {}
      options = default_options.merge options

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

    def restart_service service, options = {}
      options = default_options.merge options

      service service, 'restart', options
    end

    def reload_service service, options = {}
      options = default_options.merge options

      service service, 'reload', options
    end

    def print_service_status service, options = {}
      options = default_options.merge options
      ret = service service, 'status', options
      messages.print_output(ret, options)
      ret
    end

    # check whether a user exists on this node
    def user_exists? user, options = {}
      options = default_options.merge options

      msg = messages.add("checking if user #{user} exists", options)
      msg.parse_result(exec("id #{user}")[:exit_code])
    end

    # create a user
    def create_user user, options = {}
      options = default_options.merge options
      options[:home] ||= nil
      options[:shell] ||= nil

      return true if user_exists? user, options

      msg = messages.add("creating user #{user}", :indent => options[:indent])
      cmd = "useradd #{user} -m"
      cmd += " -d #{options[:home]}" if options[:home]
      cmd += " -s #{options[:shell]}" if options[:shell]
      msg.parse_result(exec(cmd)[:exit_code])
    end

    # returns the home directory of this user
    def get_home user, options = {}
      options = default_options(:quiet => true).merge options

      msg = messages.add("getting home directory of #{user}", options)
      ret = exec "getent passwd |cut -d':' -f1,6 |grep '^#{user}' |head -n1 |cut -d: -f2"
      if msg.parse_result(ret[:exit_code])
        return ret[:stdout].chomp
      else
        return false
      end
    end

    # returns shell of this user
    def get_shell user, options = {}
      options = default_options(:quiet => true).merge options

      msg = messages.add("getting shell of #{user}", options)
      ret = exec "getent passwd |cut -d':' -f1,7 |grep '^#{user}' |head -n1 |cut -d: -f2"
      if msg.parse_result(ret[:exit_code])
        return ret[:stdout].chomp
      else
        return false
      end
    end

    # collect additional system facts using puppets facter
    def collect_facts options = {}
      options = default_options.merge options

      # if facts already have been collected, just return
      return true if @node['operatingsystem']

      # check if lsb-release (on apt systems) and facter are installed
      # and install them if not
      if uses_apt? and not package_installed? 'lsb-release', :quiet => true
        install_package 'lsb-release', :quiet => false
      end

      unless package_installed? 'facter', :quiet => true
        return false unless install_package 'facter', :quiet => false
      end

      msg = messages.add("collecting additional system facts (using facter)", options)

      # run facter with -y for yaml output, and merge results into @node
      ret = exec 'facter -y'
      @node = YAML.load(ret[:stdout]).merge(@node)

      msg.parse_result(ret[:exit_code])
    end

    # if file is a regular file, copy it using scp
    # if it's an file.erb exists, render template and push to server
    def deploy_file file, destination, options = {}
      options = default_options(:binding => binding).merge options

      if File.exists? file
        scp file, destination, options

      elsif File.exists? "#{file}.erb"
        template = ERB.new( File.read("#{file}.erb"), nil, '%<>')
        write destination, template.result(options[:binding]), options

      else
        messages.add("'#{file}' was not found.", options).failed
      end
    end

    # create a temporary file
    def mktemp
      ret = exec('mktemp --tmpdir dust.XXXXXXXXXX')
      return false if ret[:exit_code] != 0
      ret[:stdout].chomp
    end


    private

    def method_missing method, *args, &block
      # make server nodeibutes accessible via server.nodeibute
      if @node[method.to_s]
        @node[method.to_s]

      # and as server['nodeibute']
      elsif @node[args.first]
        @node[args.first]

      # default to super
      else
        super
      end
    end

  end
end
