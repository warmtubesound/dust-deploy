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
        ::Dust.print_warning "user #{user} doesn't exist. skipping"
        next
      end

      return unless install_rvm user
      return unless install_ruby user, version
      return unless set_default user, version
    end
  end
  
  desc 'ruby_rvm:status', 'shows current ruby version'
  def status
    @config.each do |user, version|
      ::Dust.print_msg "getting current ruby-version for user #{user}"
      ret = @node.exec 'rvm use', :as_user => user
      ::Dust.print_result ret[:exit_code]
      ::Dust.print_ret ret
    end
  end


  private

  def install_rvm user
    # check if rvm is already installed
    if @node.exec('which rvm', :as_user => user)[:exit_code] == 0
      ::Dust.print_msg "updating rvm for user #{user}"
      return ::Dust.print_result @node.exec('rvm get latest', :as_user => user)[:exit_code]

    else
      ::Dust.print_msg "installing rvm for user #{user}"
      return ::Dust.print_result @node.exec("curl -s https://raw.github.com/wayneeseguin/rvm/master/binscripts/rvm-installer |bash -s stable",
                                            :as_user => user)[:exit_code]
    end
  end

  def install_ruby user, version
    return true if installed? user, version
    ::Dust.print_msg "downloading, compiling and installing ruby-#{version}"
    ::Dust.print_result  @node.exec("rvm install ruby-#{version}", :as_user => user)[:exit_code]
  end

  def set_default user, version
    ::Dust.print_msg "setting ruby-#{version} as default"
    ::Dust.print_result @node.exec("rvm use ruby-#{version} --default", :as_user => user)[:exit_code]
  end

  def installed? user, version
    ret = @node.exec "rvm list |grep ruby-#{version}", :as_user => user
    if ret[:exit_code] == 0
      return ::Dust.print_ok "ruby-#{version} for user #{user} already installed"
    end
    false
  end
end
