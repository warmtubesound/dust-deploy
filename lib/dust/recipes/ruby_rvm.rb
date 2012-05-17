class RubyRvm < Recipe
  desc 'ruby_rvm:deploy', 'installs rvm and ruby for a user'
  def deploy
    # TODO: rvm only works if your user uses bash/zsh as login shell, check

    # dependency needed by rvm
    return unless @node.install_package 'bash'
    return unless @node.install_package 'curl'

    if @node.uses_apt?
      return unless @node.install_package 'dh-autoreconf'
      return unless @node.install_package 'build-essential'
      @node.install_package 'libssl-dev'
      @node.install_package 'libyaml-dev'
      @node.install_package 'libxml2-dev'
      @node.install_package 'libxslt1-dev'
      @node.install_package 'libreadline6-dev'
      @node.install_package 'zlib1g-dev'

    elsif @node.uses_rpm?
      return unless @node.install_package 'gcc'
      return unless @node.install_package 'make'
      @node.install_package 'openssl-devel'
      @node.install_package 'libyaml-devel'
      @node.install_package 'libxml2-devel'
      @node.install_package 'libxslt-devel'
      @node.install_package 'readline-devel'
      @node.install_package 'zlib-devel'
    end

    @config.each do |user, version|
      unless @node.user_exists? user, :quiet => true
        @node.messages.add("user #{user} doesn't exist. skipping").warning
        next
      end

      return unless change_shell user
      return unless create_homedir user
      return unless install_rvm user
      return unless install_ruby user, version
      return unless set_default user, version
    end
  end

  desc 'ruby_rvm:status', 'shows current ruby version'
  def status
    @config.each do |user, version|
      msg = @node.messages.add("getting current ruby-version for user #{user}")
      ret = @node.exec 'rvm use', :as_user => user
      msg.parse_result(ret[:exit_code])
      msg.print_output(ret)
    end
  end


  private

  def install_rvm user
    # check if rvm is already installed
    if @node.exec('which rvm', :as_user => user)[:exit_code] == 0
      msg = @node.messages.add("updating rvm for user #{user}")
      return msg.parse_result(@node.exec('rvm get latest', :as_user => user)[:exit_code])

    else
      msg = @node.messages.add("installing rvm for user #{user}")
      return msg.parse_result(@node.exec("curl -s https://raw.github.com/wayneeseguin/rvm/master/binscripts/rvm-installer |bash -s stable", :as_user => user)[:exit_code])
    end
  end

  def install_ruby user, version
    return true if installed? user, version
    msg = @node.messages.add("downloading, compiling and installing ruby-#{version}")
    msg.parse_result( @node.exec("rvm install ruby-#{version}", :as_user => user)[:exit_code])
  end

  def set_default user, version
    msg = @node.messages.add("setting ruby-#{version} as default")
    msg.parse_result(@node.exec("rvm use ruby-#{version} --default", :as_user => user)[:exit_code])
  end

  def installed? user, version
    ret = @node.exec "rvm list |grep ruby-#{version}", :as_user => user
    if ret[:exit_code] == 0
      return @node.messages.add("ruby-#{version} for user #{user} already installed").ok
    end
    false
  end

  # rvm only supports bash and zsh
  def change_shell user
    shell = @node.get_shell user
    return true if shell == '/bin/zsh' or shell == '/bin/bash'

    msg = @node.messages.add("changing shell for #{user} to /bin/bash")
    msg.parse_result(@node.exec("chsh -s /bin/bash #{user}")[:exit_code])
  end

  def create_homedir user
    dir = @node.get_home user
    unless @node.dir_exists? dir, :quiet => true
      return false unless @node.mkdir dir
      return false unless @node.chown user, dir
    end
    true
  end
end
