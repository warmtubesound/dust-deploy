module Dust
  class Server
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

    # check whether a user exists on this node
    def user_exists? user, options = {}
      options = default_options.merge options

      msg = messages.add("checking if user #{user} exists", options)
      msg.parse_result(exec("id #{user}")[:exit_code])
    end

    # manages users (create, modify)
    def manage_user(user, options = {})
      options = default_options.merge(options)
      options = { 'home' => nil, 'shell' => nil, 'uid' => nil, 'remove' => false,
                  'gid' => nil, 'groups' => nil, 'system' => false }.merge(options)

      # delete user from system
      if options['remove']
        if user_exists?(user, :quiet => true)
           msg = messages.add("deleting user #{user} from system", { :indent => options[:indent] }.merge(options))
           return msg.parse_result(exec("userdel --remove #{user}")[:exit_code])
        end

        return messages.add("user #{user} not present in system", options).ok
      end

      if user_exists?(user, :quiet => true)
        args  = ""
        args << " --move-home --home #{options['home']}" if options['home']
        args << " --shell #{options['shell']}" if options['shell']
        args << " --uid #{options['uid']}" if options['uid']
        args << " --gid #{options['gid']}" if options['gid']
        args << " --append --groups #{Array(options['groups']).join(',')}" if options['groups']

        if args.empty?
          ret = messages.add("user #{user} already set up correctly", options).ok
        else
          msg = messages.add("modifying user #{user}", { :indent => options[:indent] }.merge(options))
          ret = msg.parse_result(exec("usermod #{args} #{user}")[:exit_code])
        end

      else
        args =  ""
        args =  "--create-home" unless options['system']
        args << " --system" if options['system']
        args << " --home #{options['home']}" if options['home'] and not options['system']
        args << " --shell #{options['shell']}" if options['shell']
        args << " --uid #{options['uid']}" if options['uid']
        args << " --gid #{options['gid']}" if options['gid']
        args << " --groups #{Array(options['groups']).join(',')}" if options['groups']

        msg = messages.add("creating user #{user}", { :indent => options[:indent] }.merge(options))
        ret = msg.parse_result(exec("useradd #{user} #{args}")[:exit_code])
      end

      # set selinux permissions
      chcon({ 'type' => 'user_home_dir_t' }, get_home(user), options)
      return ret
    end

    # returns the home directory of this user
    def get_home(user, options = {})
      options = default_options(:quiet => true).merge(options)

      msg = messages.add("getting home directory of #{user}", options)
      ret = exec("getent passwd |cut -d':' -f1,6 |grep '^#{user}' |head -n1 |cut -d: -f2")
      if msg.parse_result(ret[:exit_code]) and not ret[:stdout].chomp.empty?
        return ret[:stdout].chomp
      else
        return false
      end
    end

    # returns shell of this user
    def get_shell(user, options = {})
      options = default_options(:quiet => true).merge(options)

      msg = messages.add("getting shell of #{user}", options)
      ret = exec("getent passwd |cut -d':' -f1,7 |grep '^#{user}' |head -n1 |cut -d: -f2")
      if msg.parse_result(ret[:exit_code])
        return ret[:stdout].chomp
      else
        return false
      end
    end

    # returns primary group id of this user
    def get_gid(user, options = {})
      options = default_options(:quiet => true).merge(options)

      msg = messages.add("getting primary gid of #{user}", options)
      ret = exec("id -g #{user}")
      if msg.parse_result(ret[:exit_code])
        return ret[:stdout].chomp
      else
        return false
      end
    end
  end
end
