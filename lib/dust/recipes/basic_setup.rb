class BasicSetup < Thor
  desc 'basic_setup:deploy', 'installs basic packages and config files'
  def deploy node, ingredients, options
    template_path = "./templates/#{ File.basename(__FILE__).chomp( File.extname(__FILE__) ) }"

    # install some basic packages
    ::Dust.print_msg "installing basic packages\n"

    node.install_package 'screen', :indent => 2
    node.install_package 'rsync', :indent => 2
    node.install_package 'psmisc', :indent => 2 if node.uses_apt? :quiet => true

    if node.uses_rpm? :quiet => true
      node.install_package 'vim-enhanced', :indent => 2
    else
      node.install_package 'vim', :indent => 2
    end

    if node.uses_apt? :quiet => true
      node.install_package 'git-core', :indent => 2
    else
      node.install_package 'git', :indent => 2
    end
    puts
    
    # deploy basic configuration for root user
    ::Dust.print_msg "deploying configuration files for root\n"
    Dir["#{template_path}/.*"].each do |file|
      next unless File.file? file
      node.scp file, "/root/#{File.basename file}", :indent => 2
    end

  end
end

