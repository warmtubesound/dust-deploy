class BasicSetup < Recipe
  desc 'basic_setup:deploy', 'installs basic packages and config files'
  def deploy 
    # install some basic packages
    ::Dust.print_msg "installing basic packages\n"

    @node.install_package 'tmux', :indent => 2
    @node.install_package 'rsync', :indent => 2
    @node.install_package 'psmisc', :indent => 2 if @node.uses_apt?

    if @node.uses_rpm?
      @node.install_package 'vim-enhanced', :indent => 2
    else
      @node.install_package 'vim', :indent => 2
    end

    if @node.uses_apt?
      @node.install_package 'git-core', :indent => 2
    else
      @node.install_package 'git', :indent => 2
    end
    puts
    
    # deploy basic configuration for root user
    ::Dust.print_msg "deploying configuration files for root\n"
    Dir["#{@template_path}/.*"].each do |file|
      next unless File.file? file
      @node.deploy_file file, "/root/#{File.basename file}", { :binding => binding, :indent => 2 }
    end

  end
end

