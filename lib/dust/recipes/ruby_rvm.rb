class RubyRvm < Recipe
  desc 'ruby_rvm:deploy', 'installs and sets specified ruby version using rvm'
  def deploy
    return ::Dust.failed 'os currently not supported :/' unless @node.is_ubuntu?

    return unless @node.install_package 'ruby-rvm'
    return unless @node.install_package 'libyaml-dev' # needed for yaml output, otherwise gem complains

    return unless install_ruby @config
    return unless set_default @config 
  end
  
  desc 'ruby_rvm:status', 'shows current ruby version'
  def status
    ::Dust.print_msg 'getting current ruby-version'
    ret = @node.exec 'rvm use'
    ::Dust.print_result ret[:exit_code]
    ::Dust.print_ret ret
  end


  private

  def install_ruby version
    return true if installed? version
    ::Dust.print_msg "downloading, compiling and installing ruby-#{version}\n"
    ret = @node.exec "rvm install ruby-#{version}", :live => true
    return ::Dust.print_failed 'error installing ruby' unless ret[:exit_code] == 0
    true
  end

  def set_default version
    ::Dust.print_msg "setting ruby-#{version} as system default\n"
    ret = @node.exec "rvm use ruby-#{version} --default", :live => true
    return ::Dust.print_failed "error setting default ruby version"  unless ret[:exit_code] == 0
    true
  end

  def installed? version
    ret = @node.exec "rvm list |grep ruby-#{version}"
    if ret[:exit_code] == 0
      return ::Dust.print_ok "ruby-#{version} already installed"
    end
    false
  end
end
