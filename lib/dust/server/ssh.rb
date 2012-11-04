require 'net/ssh'
require 'net/scp'
require 'net/ssh/proxy/socks5'

require 'dust/server/file'
require 'dust/server/osdetect'
require 'dust/server/package'
require 'dust/server/selinux'

module Dust
  class Server
    attr_reader :ssh

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

    def exec(command, options={:live => false, :as_user => false})
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
            if data =~ /\[sudo\] password for #{@node['user']}/

              raise 'password requested, but none given in config!' if @node['password'].empty?
              raise 'already sent password, but sudo requested the password again. (wrong password?)' if sudo_authenticated

              # we're not authenticated yet, send password
              channel.send_data "#{@node['password']}\n"
              sudo_authenticated = true

            else
              # skip everything util authenticated (if sudo is used and password given in config)
              next if @node['sudo'] and not @node['password'].empty? and not sudo_authenticated

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

    def scp(source, destination, options={})
      options = default_options.merge(options)

      # make sure scp is installed on client
      install_package('openssh-clients', :quiet => true) if uses_rpm?

      msg = messages.add("deploying #{File.basename source}", options)

      # check if destination is a directory
      is_dir = dir_exists?(destination, :quiet => true)

      # save permissions if the file already exists
      ret = exec("stat -c %a:%u:%g #{destination}")
      if ret[:exit_code] == 0 and not is_dir
        permissions, user, group = ret[:stdout].chomp.split(':')
      else
        # files = 644, dirs = 755
        permissions = 'ug-x,o-wx,u=rwX,g=rX,o=rX'
        user = 'root'
        group = 'root'
      end

      # if in sudo mode, copy file to temporary place, then move using sudo
      if @node['sudo']
        tmpdir = mktemp(:type => 'directory')
        return msg.failed('could not create temporary directory (needed for sudo)') unless tmpdir

        # temporary destination in tmpdir
        tmpdest = "#{tmpdir}/#{File.basename(destination)}"

        # allow user to write file without sudo (for scp)
        # then change file back to root, and copy to the destination
        chown(@node['user'], tmpdir, :quiet => true)
        @ssh.scp.upload!(source, tmpdest, :recursive => true)

        # set file permissions
        chown("#{user}:#{group}", tmpdest, :quiet => true) if user and group
        chmod(permissions, tmpdest, :quiet => true)

        # if destination is a directory, append real filename
        destination = "#{destination}/#{File.basename(source)}" if is_dir

        # move the file from the temporary location to where it actually belongs
        msg.parse_result(exec("mv -f #{tmpdest} #{destination}")[:exit_code])

        # remove temporary directory
        rm(tmpdir, :quiet => true)

      else
        @ssh.scp.upload!(source, destination, :recursive => true)
        msg.ok

        # set file permissions
        chown("#{user}:#{group}", destination, :quiet => true) if user and group
        chmod(permissions, destination, :quiet => true)
      end

      restorecon(destination, options) # restore SELinux labels
    end

    # download a file (sudo not yet supported)
    def download(source, destination, options={})
      options = default_options.merge(options)

      # make sure scp is installed on client
      install_package('openssh-clients', :quiet => true) if uses_rpm?

      msg = messages.add("downloading #{File.basename source}", options)
      msg.parse_result(@ssh.scp.download!(source, destination))
    end
  end
end
