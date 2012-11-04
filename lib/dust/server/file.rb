require 'erb'
require 'tempfile'
require 'dust/server/ssh'
require 'dust/server/selinux'

module Dust
  class Server
    def write(destination, content, options={})
      options = default_options.merge(options)

      msg = messages.add("deploying #{File.basename destination}", options)

      f = Tempfile.new('dust-write')
      f.print(content)
      f.close

      ret = msg.parse_result(scp(f.path, destination, :quiet => true))
      f.unlink

      ret
    end

    def append(destination, newcontent, options={})
      options = default_options.merge(options)

      msg = messages.add("appending to #{File.basename destination}", options)

      content = exec("cat #{destination}")[:stdout]
      content.concat(newcontent)

      msg.parse_result(write(destination, content, :quiet => true))
    end

    # if file is a regular file, copy it using scp
    # if it's an file.erb exists, render template and push to server
    def deploy_file(file, destination, options={})
      options = default_options(:binding => binding).merge(options)

      if File.exists?(file)
        scp(file, destination, options)

      elsif File.exists?("#{file}.erb")
        template = ERB.new( File.read("#{file}.erb"), nil, '%<>')
        write(destination, template.result(options[:binding]), options)

      else
        messages.add("'#{file}' was not found.", options).failed
      end
    end

    # create a temporary file
    def mktemp(options={:type => 'file'})
      if options[:type] == 'file'
        ret = exec('mktemp --tmpdir dust.XXXXXXXXXX')
      elsif options[:type] == 'directory'
        ret = exec('mktemp -d --tmpdir dust.XXXXXXXXXX')
      else
        return messages.add("mktemp: unknown type '#{options[:type]}'").failed
      end

      return false if ret[:exit_code] != 0
      ret[:stdout].chomp
    end

    def symlink(source, destination, options={})
      options = default_options.merge(options)

      msg = messages.add("symlinking #{File.basename source} to '#{destination}'", options)
      ret = msg.parse_result(exec("ln -s #{source} #{destination}")[:exit_code])
      restorecon(destination, options) # restore SELinux labels
      ret
    end

    def chmod(mode, file, options={})
      options = default_options.merge(options)

      msg = messages.add("setting mode of #{File.basename file} to #{mode}", options)
      msg.parse_result(exec("chmod -R #{mode} #{file}")[:exit_code])
    end

    def chown(user, file, options={})
      options = default_options.merge(options)

      msg = messages.add("setting owner of #{File.basename file} to #{user}", options)
      msg.parse_result(exec("chown -R #{user} #{file}")[:exit_code])
    end


    def rm(file, options={})
      options = default_options.merge(options)

      msg = messages.add("deleting #{file}", options)
      msg.parse_result(exec("rm -rf #{file}")[:exit_code])
    end

    def cp(source, destination, options={})
      options = default_options.merge(options)

      # get rid of overly careful aliases
      exec 'unalias -a'

      msg = messages.add("copying #{source} to #{destination}", options)
      msg.parse_result(exec("cp -a #{source} #{destination}")[:exit_code])
    end

    def mv(source, destination, options={})
      options = default_options.merge(options)

      # get rid of overly careful aliases
      exec 'unalias -a'

      msg = messages.add("moving #{source} to #{destination}", options)
      msg.parse_result(exec("mv #{source} #{destination}")[:exit_code])
    end

    def mkdir(dir, options={})
      options = default_options.merge(options)

      return true if dir_exists?(dir, :quiet => true)

      msg = messages.add("creating directory #{dir}", options)
      ret = msg.parse_result(exec("mkdir -p #{dir}")[:exit_code])
      restorecon(dir, options) # restore SELinux labels
      ret
    end

    def is_executable?(file, options={})
      options = default_options.merge(options)

      msg = messages.add("checking if file #{file} exists and is executeable", options)
      msg.parse_result(exec("test -x $(which #{file})")[:exit_code])
    end

    def file_exists?(file, options={})
      options = default_options.merge(options)

      msg = messages.add("checking if file #{file} exists", options)

      # don't treat directories as files
      return msg.failed if dir_exists?(file, :quiet => true)

      msg.parse_result(exec("test -e #{file}")[:exit_code])
    end

    def dir_exists?(dir, options={})
      options = default_options.merge(options)

      msg = messages.add("checking if directory #{dir} exists", options)
      msg.parse_result(exec("test -d #{dir}")[:exit_code])
    end
  end
end
