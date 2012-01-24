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
  
    def exec command
      stdout = ''
      stderr = ''
      exit_code = nil
      exit_signal = nil
  
      @ssh.open_channel do |channel|
        channel.exec command do |ch, success|
          abort "FAILED: couldn't execute command (ssh.channel.exec)" unless success
          channel.on_data { |ch, data| stdout += data }
          channel.on_extended_data { |ch, type, data| stderr += data }
          channel.on_request('exit-status') { |ch, data| exit_code = data.read_long }
          channel.on_request('exit-signal') { |ch, data| exit_signal = data.read_long }
        end
      end
  
      @ssh.loop
  
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

      Dust.print_msg "deploying #{File.basename source}", options
      @ssh.scp.upload! source, destination
      Dust.print_ok '', options
      restorecon destination, options # restore SELinux labels
    end
  
    def symlink source, destination, options = {}
      options = default_options.merge options

      Dust.print_msg "symlinking #{File.basename source} to '#{destination}'", options
      Dust.print_result exec("ln -s #{source} #{destination}")[:exit_code], options
      restorecon destination, options # restore SELinux labels
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

    def mkdir dir, options = {}
      options = default_options.merge options

      return true if dir_exists? dir, :quiet => true

      Dust.print_msg "creating directory #{dir}", options
      Dust.print_result exec("mkdir -p #{dir}")[:exit_code], options
      restorecon dir, options # restore SELinux labels
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
      
      if package_installed? package, :quiet=>true
        return Dust.print_ok "package #{package} already installed"
      end

      Dust.print_msg "installing #{package}", :indent => options[:indent] + 1

      if uses_apt?
        exec "DEBIAN_FRONTEND=noninteractive aptitude install -y #{package}"
      elsif uses_emerge?
        exec "#{options[:env]} emerge #{package}"
      elsif uses_rpm?
        exec "yum install -y #{package}"
      else
        Dust.print_failed 'install_package only supports apt, emerge and rpm systems at the moment'
      end

      # check if package actually was installed
      Dust.print_result package_installed? package, :quiet => true
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

      if uses_apt?
        Dust.print_result exec('aptitude update')[:exit_code], options
      elsif uses_emerge?
        Dust.print_result exec('emerge --sync')[:exit_code], options
      elsif uses_rpm?
        Dust.print_result exec('yum check-update')[:exit_code], options
      else
        Dust.print_failed '', options
      end
    end

    def system_update options = {}
      options = default_options.merge options

      Dust.print_msg 'installing system updates', options

      if uses_apt?
        ret = exec 'DEBIAN_FRONTEND=noninteractive aptitude full-upgrade -y'
      elsif uses_emerge?
        ret = exec 'emerge -uND @world'
      elsif uses_rpm?
        ret = exec 'yum upgrade -y'
      else
        Dust.print_failed "\nsystem not (yet) supported", options
        return false
      end
     
      Dust.print_result ret[:exit_code], options 

      # display stderr and stdout
      puts
      puts "#{Dust.grey}#{ret[:stdout]}#{Dust.none}"
      puts "#{Dust.red}#{ret[:stderr]}#{Dust.none}"
    end

    # determining the system packet manager has to be done without facter
    # because it's used to find out whether facter is installed / install facter
    def uses_apt? options = {}
      options = default_options(:quiet => true).merge options

      Dust.print_msg 'determining whether node uses apt', options
      Dust.print_result exec('test -e /etc/debian_version')[:exit_code], options
    end

    def uses_rpm? options = {}
      options = default_options(:quiet => true).merge options

      Dust.print_msg 'determining whether node uses rpm', options
      Dust.print_result exec('test -e /etc/redhat-release')[:exit_code], options
    end

    def uses_emerge? options = {}
      options = default_options(:quiet => true).merge options

      Dust.print_msg 'determining whether node uses emerge', options
      Dust.print_result exec('test -e /etc/gentoo-release')[:exit_code], options
    end
  
    def is_os? os_list, options = {}
      options = default_options(:quiet => true).merge options

      Dust.print_msg "checking if this machine runs #{os_list.join(' or ')}", options
      collect_facts options unless @node['operatingsystem']

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

      is_os? ['debian'], options
    end
  
    def is_ubuntu? options = {}
      options = default_options(:quiet => true).merge options

      is_os? ['ubuntu'], options
    end
  
    def is_gentoo? options = {}
      options = default_options(:quiet => true).merge options

      is_os? ['gentoo'], options
    end
  
    def is_centos? options = {}
      options = default_options(:quiet => true).merge options

      is_os? ['centos'], options
    end
  
    def is_scientific? options = {}
      options = default_options(:quiet => true).merge options

      is_os? ['scientific'], options
    end

    def is_fedora? options = {}
      options = default_options(:quiet => true).merge options

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
        Dust.print_result exec("chkconfig #{service} on")[:exit_code], options
      elsif uses_apt?
        Dust.print_result exec("update-rc.d #{service} defaults")[:exit_code], options
      elsif uses_emerge?
        Dust.print_result exec("rc-update add #{service} default")[:exit_code], options
      end
    end
 
    def restart_service service, options = {}
      options = default_options.merge options

      Dust.print_msg "restarting #{service}", options
      Dust.print_result exec("/etc/init.d/#{service} restart")[:exit_code], options
    end
  
    def reload_service service, options = {}
      options = default_options.merge options

      Dust.print_msg "reloading #{service}", options
      Dust.print_result exec("/etc/init.d/#{service} reload")[:exit_code], options
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

    # collect additional system facts using puppets facter
    def collect_facts options = {}
      options = default_options.merge options


      # check if lsb-release (on apt systems) and facter are installed
      # and install them if not
      if uses_apt? and not package_installed? 'lsb-release', :quiet => true
        install_package 'lsb-release', :quiet => false
      end

      unless package_installed? 'facter', :quiet => true
        install_package 'facter', :quiet => false
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
