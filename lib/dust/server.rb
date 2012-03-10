require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'net/ssh/proxy/socks5'
require 'erb'
require 'tempfile'

module Dust
  class Server
    attr_reader :ssh
  
    def default_options options = {}
      { :quiet => false, :indent => 1 }.merge options
    end
    
    def initialize node
      @node = node
      @node['user'] ||= 'root'
      @node['port'] ||= 22
      @node['password'] ||= ''
      @node['sudo'] ||= false
    end

    def connect 
      Dust.print_hostname @node['hostname']
      begin
        # connect to proxy if given
        if @node['proxy']
          host, port = @node['proxy'].split ':'
          proxy = Net::SSH::Proxy::SOCKS5.new host, port
        else
          proxy = nil
        end

        @ssh = Net::SSH.start @node['fqdn'], @node['user'],
                              { :password => @node['password'],
                                :port => @node['port'],
                                :proxy => proxy }
      rescue Exception
        error_message = "coudln't connect to #{@node['fqdn']}"
        error_message += " (via socks5 proxy #{@node['proxy']})" if proxy
        Dust.print_failed error_message
        return false
      end

      true
    end
  
    def disconnect
      @ssh.close
    end
  
    def exec command, options={:live => false}
      sudo_authenticated = false
      stdout = ''
      stderr = ''
      exit_code = nil
      exit_signal = nil

      @ssh.open_channel do |channel|
        
        # request a terminal (sudo needs it)
        # and prepend "sudo"
        if @node['sudo']          
          channel.request_pty
          command = "sudo #{command}"
        end
        
        channel.exec command do |ch, success|
          abort "FAILED: couldn't execute command (ssh.channel.exec)" unless success
          
          channel.on_data do |ch, data|
            # only send password if sudo mode is enabled,
            # sudo password string matches
            # and only send password once in a session (trying to prevent attacks reading out the password)
            if @node['sudo'] and data =~ /^\[sudo\] password for #{@node['user']}/ and not sudo_authenticated
              channel.send_data "#{@node['password']}\n"
              sudo_authenticated = true
            else
              stdout += data
            end

            Dust.print_msg "#{Dust.green 0}#{data}#{Dust.none}", :indent => 0 if options[:live] and not data.empty?
          end

          channel.on_extended_data do |ch, type, data|
            stderr += data
            Dust.print_msg "#{Dust.red 0}#{data}#{Dust.none}", :indent => 0 if options[:live] and not data.empty?
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
      
      Dust.print_msg "deploying #{File.basename destination}", options
      
      f = Tempfile.new 'dust-write'
      f.print content
      f.close
      
      ret = Dust.print_result scp(f.path, destination, :quiet => true), options
      f.unlink
      
      ret
    end

    def append destination, newcontent, options = {}
      options = default_options.merge options
      
      Dust.print_msg "appending to #{File.basename destination}", options
      
      content = exec("cat #{destination}")[:stdout]
      content.concat newcontent
      
      Dust.print_result write(destination, content, :quiet => true), options      
    end
 
    def scp source, destination, options = {}
      options = default_options.merge options

      # make sure scp is installed on client
      install_package 'openssh-clients', :quiet => true if uses_rpm?

      Dust.print_msg "deploying #{File.basename source}", options

      # if in sudo mode, copy file to temporary place, then move using sudo
      if @node['sudo'] 
        ret = exec 'mktemp --tmpdir dust.XXXXXXXXXX' 
        if ret[:exit_code] != 0
          ::Dust.print_failed 'could not create temporary file (needed for sudo)'
          return false
        end

        tmpfile = ret[:stdout].chomp

        # allow user to write file without sudo (for scp)
        # then change file back to root, and copy to the destination
        chown @node['user'], tmpfile, :quiet => true
        @ssh.scp.upload! source, tmpfile
        chown 'root', tmpfile, :quiet => true
        Dust.print_result exec("mv -f #{tmpfile} #{destination}")[:exit_code], options

      else
        @ssh.scp.upload! source, destination
        Dust.print_ok '', options
      end

      restorecon destination, options # restore SELinux labels
    end
  
    def symlink source, destination, options = {}
      options = default_options.merge options

      Dust.print_msg "symlinking #{File.basename source} to '#{destination}'", options
      ret = Dust.print_result exec("ln -s #{source} #{destination}")[:exit_code], options
      restorecon destination, options # restore SELinux labels
      ret
    end
  
    def chmod mode, file, options = {}
      options = default_options.merge options

      Dust.print_msg "setting mode of #{File.basename file} to #{mode}", options
      Dust.print_result exec("chmod -R #{mode} #{file}")[:exit_code], options
    end

    def chown user, file, options = {}
      options = default_options.merge options

      Dust.print_msg "setting owner of #{File.basename file} to #{user}", options
      Dust.print_result exec("chown -R #{user} #{file}")[:exit_code], options
    end

    def rm file, options = {}
      options = default_options.merge options

      Dust.print_msg "deleting #{file}", options
      Dust.print_result exec("rm -rf #{file}")[:exit_code], options
    end

    def cp source, destination, options = {}
      options = default_options.merge options

      Dust.print_msg "copying #{source} to #{destination}", options
      Dust.print_result exec("cp -a #{source} #{destination}")[:exit_code], options
    end

    def mv source, destination, options = {}
      options = default_options.merge options

      Dust.print_msg "moving #{source} to #{destination}", options
      Dust.print_result exec("mv #{source} #{destination}")[:exit_code], options
    end

    def mkdir dir, options = {}
      options = default_options.merge options

      return true if dir_exists? dir, :quiet => true

      Dust.print_msg "creating directory #{dir}", options
      ret = Dust.print_result exec("mkdir -p #{dir}")[:exit_code], options
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

      Dust.print_msg "restoring selinux labels for #{path}", options
      Dust.print_result exec("#{ret[:stdout].chomp} -R #{path}")[:exit_code], options
    end
 
    def get_system_users options = {}
      options = default_options.merge options
 
      Dust.print_msg "getting all system users", options
      ret = exec 'getent passwd |cut -d: -f1'
      Dust.print_result ret[:exit_code], options

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

      Dust.print_msg "checking if #{packages.join(' or ')} is installed", options

      packages.each do |package|
        if uses_apt?
          return Dust.print_ok '', options unless exec("dpkg -s #{package} |grep 'install ok'")[:stdout].empty?
        elsif uses_emerge?
          return Dust.print_ok '', options unless exec("qlist -I #{package}")[:stdout].empty?
        elsif uses_rpm?
          return Dust.print_ok '', options if exec("rpm -q #{package}")[:exit_code] == 0
        end
      end

      Dust.print_failed '', options
    end
 
    def install_package package, options = {}
      options = default_options.merge options
      options[:env] ||= ''
      
      if package_installed? package, :quiet => true
        return Dust.print_ok "package #{package} already installed", options
      end

      Dust.print_msg "installing #{package}", options

      if uses_apt?
        exec "DEBIAN_FRONTEND=noninteractive aptitude install -y #{package}"
      elsif uses_emerge?
        exec "#{options[:env]} emerge #{package}"
      elsif uses_rpm?
        exec "yum install -y #{package}"
      else
        Dust.print_failed 'install_package only supports apt, emerge and rpm systems at the moment', options
      end

      # check if package actually was installed
      Dust.print_result package_installed?(package, :quiet => true), options
    end

    def remove_package package, options = {}
      options = default_options.merge options

      unless package_installed? package, :quiet => true
        return Dust.print_ok "package #{package} not installed", options
      end

      Dust.print_msg "removing #{package}", options
      if uses_apt?
        Dust.print_result exec("DEBIAN_FRONTEND=noninteractive aptitude purge -y #{package}")[:exit_code], options
      elsif uses_emerge?
        Dust.print_result exec("emerge --unmerge #{package}")[:exit_code], options
      elsif uses_rpm?
        Dust.print_result exec("yum erase -y #{package}")[:exit_code], options
      else
        Dust.print_failed '', options
      end
    end

    def update_repos options = {}
      options = default_options.merge options

      Dust.print_msg 'updating system repositories', options
      puts if options[:live]

      if uses_apt?
        ret = exec 'aptitude update', options
      elsif uses_emerge?
        ret = exec 'emerge --sync', options
      elsif uses_rpm?
        ret = exec 'yum check-update', options

        # yum returns != 0 if packages that need to be updated are found
        # we don't want that this is producing an error
        ret[:exit_code] = 0 if ret[:exit_code] == 100
      else
        return Dust.print_failed '', options
      end

      if options[:live]
        puts
      else
        Dust.print_result ret[:exit_code], options
      end
 
      ret[:exit_code]
    end

    def system_update options = {}
      options = default_options.merge(:live => true).merge(options)
    
      update_repos
      
      Dust.print_msg 'installing system updates', options
      puts if options[:live]

      if uses_apt?
        ret = exec 'DEBIAN_FRONTEND=noninteractive aptitude full-upgrade -y', options
      elsif uses_emerge?
        ret = exec 'emerge -uND @world', options
      elsif uses_rpm?
        ret = exec 'yum upgrade -y', options
      else
        Dust.print_failed 'system not (yet) supported', options
        return false
      end

      if options[:live] 
        puts
      else
        Dust.print_result ret[:exit_code], options
      end

      ret[:exit_code]
    end

    # determining the system packet manager has to be done without facter
    # because it's used to find out whether facter is installed / install facter
    def uses_apt? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_apt if @uses_apt
      Dust.print_msg 'determining whether node uses apt', options
      @uses_apt = Dust.print_result exec('test -e /etc/debian_version')[:exit_code], options
    end

    def uses_rpm? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_rpm if @uses_rpm
      Dust.print_msg 'determining whether node uses rpm', options
      @uses_rpm = Dust.print_result exec('test -e /etc/redhat-release')[:exit_code], options
    end

    def uses_emerge? options = {}
      options = default_options(:quiet => true).merge options

      return @uses_emerge if @uses_emerge
      Dust.print_msg 'determining whether node uses emerge', options
      @uses_emerge = Dust.print_result exec('test -e /etc/gentoo-release')[:exit_code], options
    end
  
    def is_os? os_list, options = {}
      options = default_options(:quiet => true).merge options

      Dust.print_msg "checking if this machine runs #{os_list.join(' or ')}", options      
      return Dust.print_failed '', options unless collect_facts options

      os_list.each do |os|
        if @node['operatingsystem'].downcase == os.downcase
          return Dust.print_ok '', options
        end
      end

      Dust.print_failed '', options
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
  
    def is_executable? file, options = {}
      options = default_options.merge options

      Dust.print_msg "checking if file #{file} exists and is executeable", options
      Dust.print_result exec("test -x $(which #{file})")[:exit_code], options
    end
  
    def file_exists? file, options = {}
      options = default_options.merge options

      Dust.print_msg "checking if file #{file} exists", options
      Dust.print_result exec("test -e #{file}")[:exit_code], options
    end

    def dir_exists? dir, options = {}
      options = default_options.merge options

      Dust.print_msg "checking if directory #{dir} exists", options
      Dust.print_result exec("test -d #{dir}")[:exit_code], options
    end
 
    def autostart_service service, options = {}
      options = default_options.merge options

      Dust.print_msg "autostart #{service} on boot", options

      if uses_rpm?
        if file_exists? '/bin/systemctl', :quiet => true
          Dust.print_result exec("systemctl enable #{service}.service")[:exit_code], options
        else
          Dust.print_result exec("chkconfig #{service} on")[:exit_code], options
        end

      elsif uses_apt?
        Dust.print_result exec("update-rc.d #{service} defaults")[:exit_code], options

      elsif uses_emerge?
        Dust.print_result exec("rc-update add #{service} default")[:exit_code], options
      end
    end

    # invoke 'command' on the service (e.g. @node.service 'postgresql', 'restart') 
    def service service, command, options = {}
      options = default_options.merge options

      return ::Dust.print_failed "service: '#{service}' unknown", options unless service.is_a? String

      # try systemd, then upstart, then sysvconfig, then initscript
      if file_exists? '/bin/systemctl', :quiet => true
        Dust.print_msg "#{command}ing #{service} (via systemd)", options
        ret = exec("systemctl #{command} #{service}.service")

      elsif file_exists? "/etc/init/#{service}", :quiet => true
        Dust.print_msg "#{command}ing #{service} (via upstart)", options
        ret = exec("#{command} #{service}")

      elsif file_exists? '/sbin/service', :quiet => true or file_exists? '/usr/sbin/service', :quiet => true
        Dust.print_msg "#{command}ing #{service} (via sysvconfig)", options
        ret = exec("service #{service} #{command}")

      else
        Dust.print_msg "#{command}ing #{service} (via initscript)", options
        ret = exec("/etc/init.d/#{service} #{command}")
      end

      Dust.print_result ret[:exit_code], options
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
      Dust.print_ret ret, options
      ret
    end

    # check whether a user exists on this node
    def user_exists? user, options = {}
      options = default_options.merge options

      Dust.print_msg "checking if user #{user} exists", options
      Dust.print_result exec("id #{user}")[:exit_code], options
    end

    # create a user
    def create_user user, options = {}
      options = default_options.merge options
      options[:home] ||= nil
      options[:shell] ||= nil
      
      return true if user_exists? user, options

      Dust.print_msg "creating user #{user}", :indent => options[:indent]
      cmd = "useradd #{user} -m"
      cmd += " -d #{options[:home]}" if options[:home]
      cmd += " -s #{options[:shell]}" if options[:shell]
      Dust.print_result exec(cmd)[:exit_code], options
    end

    # returns the home directory of this user
    def get_home user, options = {}
      options = default_options(:quiet => true).merge options
      
      Dust.print_msg "getting home directory of #{user}"
      ret = exec "getent passwd |cut -d':' -f1,6 |grep '^#{user}' |head -n1 |cut -d: -f2"
      if Dust.print_result ret[:exit_code]     
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

      Dust.print_msg "collecting additional system facts (using facter)", options

      # run facter with -y for yaml output, and merge results into @node
      ret = exec 'facter -y'
      @node.merge! YAML.load ret[:stdout]

      Dust.print_result ret[:exit_code], options
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
        ::Dust.print_failed "'#{file}' was not found."
      end
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
