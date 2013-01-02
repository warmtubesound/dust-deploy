require 'dust/server/ssh'

module Dust
  class Server
    def selinuxenabled?
      return true if exec('selinuxenabled')[:exit_code] == 0
      false
    end

    # check if restorecon (selinux) is available
    # if so, run it on "path" recursively
    def restorecon(path, options={})
      options = default_options.merge(options)

      # if selinux is not enabled, just return
      return true unless selinuxenabled?

      msg = messages.add("restoring selinux labels for #{path}", options)
      msg.parse_result(exec("restorecon -R #{path}")[:exit_code])
    end

    def chcon(permissions, file, options={})
      options = default_options.merge(options)

      # just return if selinux is not enabled
      return true unless selinuxenabled?

      args  = ""
      args << " --type #{permissions['type']}" if permissions['type']
      args << " --recursive #{permissions['recursive']}" if permissions['recursive']
      args << " --user #{permissions['user']}" if permissions['user']
      args << " --range #{permissions['range']}" if permissions['range']
      args << " --role #{permissions['role']}" if permissions['role']

      msg = messages.add("setting selinux permissions of #{File.basename(file)}", options)
      msg.parse_result(exec("chcon #{args} #{file}")[:exit_code])
    end

  end
end
