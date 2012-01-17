class HashCheck < Recipe
  
  desc 'hash_check:deploy', 'checks /etc/shadow for weak hashes'
  def deploy
    # mkpasswd is in the package 'whois' resp. 'expect'
    @node.install_package 'whois' if @node.uses_apt?
    @node.install_package 'expect' if @node.uses_rpm?

    # those keys indicate that no password is set, or login is disabled
    keys = [ '*', '!', '!!', '', 'LK', 'NP' ]

    # mapping the magic numbers to the actual hash algorithms
    algorithms = { '1' => 'md5', '2' => 'blowfish', '5' => 'sha-256', '6' => 'sha-512' }

    weak_passwords = File.open "#{@template_path}/weak_passwords", 'r'
    shadow = @node.exec('cat /etc/shadow')[:stdout]

    ::Dust.print_msg "checking for weak password hashes\n"

    found_weak = false

    shadow.each do |line|
      user, hash = line.split(':')[0..1]
      next if keys.include? hash
      method, salt = hash.split('$')[1..2]
  
      weak_passwords.each_line do |password|
        password.chomp!

        # generate the hash for this password, according to salt and method
        weak_hash = @node.exec("mkpasswd -m #{algorithms[method.to_s]} -S '#{salt}' '#{password}'")[:stdout]
        weak_hash.chomp!

        if weak_hash == hash
          ::Dust.print_failed "user #{user} has a weak password! (#{password})", :indent => 2
          found_weak= true
        end
      end
    end

    weak_passwords.close
    ::Dust.print_ok 'none found.', :indent => 2 unless found_weak
  end
end
