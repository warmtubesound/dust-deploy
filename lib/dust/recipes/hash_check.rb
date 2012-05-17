class HashCheck < Recipe

  desc 'hash_check:deploy', 'checks /etc/shadow for weak hashes'
  def deploy
    # those keys indicate that no password is set, or login is disabled
    keys = [ '*', '!', '!!', '', 'LK', 'NP' ]

    weak_passwords = File.open "#{@template_path}/weak_passwords", 'r'

    shadow = @node.exec('getent shadow')[:stdout]
    msg = @node.messages.add("checking for weak password hashes\n")

    found_weak = false
    shadow.each_line do |line|
      user, hash = line.split(':')[0..1]
      next if keys.include? hash
      method, salt = hash.split('$')[1..2]

      weak_passwords.each_line do |password|
        password.chomp!

        # python was imho the best solution to generate /etc/shadow hashes.
        # mkpasswd doesn't work on centos-like machines :/
        # and python is more likely installed than ruby
        ret = @node.exec("python -c \"import crypt; print(crypt.crypt('#{password}', '\\$#{method}\\$#{salt}\\$'));\"")

        unless ret[:exit_code] == 0
          return msg.failed('error during hash creation (is python installed?)')
        end
        if hash == ret[:stdout].chomp
          msg.failed("user #{user} has a weak password! (#{password})")
          found_weak = true
        end
      end
    end

    weak_passwords.close
    msg.ok('none found.') unless found_weak
  end
end
