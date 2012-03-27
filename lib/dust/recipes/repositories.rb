class Repositories < Recipe
  desc 'repositories:deploy', 'configures package management repositories (aptitude, yum)'
  def deploy
    @node.collect_facts

    delete_old_repositories
    deploy_repositories
    
    # fetch new stuff
    puts
    @node.update_repos if options.restart? or options.reload?        
  end
  
  
  private
  
  # deletes all .list files under /etc/apt/sources.list.d
  def delete_old_repositories
    :: Dust.print_msg 'deleting old repositories'
    @node.rm '/etc/apt/sources.list.d/*.list', :quiet => true if @node.uses_apt?
    ::Dust.print_ok     
  end
  
  def deploy_repositories
    @config.each do |name, repo|

      # if repo is present but not a hash use defaults
      repo = {} unless repo.is_a? Hash

      merge_with_default_settings repo
      
      # the default repository in /etc/apt/sources.list (debian)
      if name == 'default'
        ::Dust.print_msg 'deploying default repository'        
        sources = generate_default_repo repo 
        ::Dust.print_result @node.write('/etc/apt/sources.list', sources, :quiet => true)        
      else
        ::Dust.print_msg "adding repository '#{name}' to sources"        
        sources = generate_repo repo
        ::Dust.print_result @node.write("/etc/apt/sources.list.d/#{name}.list", sources, :quiet => true)        
        add_repo_key name, repo
      end
    end
  end

  # merge repo configuration with default settings
  def merge_with_default_settings repo
    # setting defaults
    repo['url'] ||= 'http://ftp.debian.org/debian/' if @node.is_debian?
    repo['url'] ||= 'http://archive.ubuntu.com/ubuntu/' if @node.is_ubuntu?
    
    repo['release'] ||= @node['lsbdistcodename']
    repo['components'] ||= 'main'
    
    # ||= doesn't work for booleans
    repo['source'] = repo['source'].nil? ? true : repo['source']
    repo['binary'] = repo['binary'].nil? ? true : repo['binary']
  end  
  
  def generate_default_repo repo
    sources = ''
    sources.concat "deb #{repo['url']} #{repo['release']} #{repo['components']}\n"
    sources.concat "deb-src #{repo['url']} #{repo['release']} #{repo['components']}\n\n"
    
    # security
    if @node.is_debian?
      sources.concat "deb http://security.debian.org/ #{repo['release']}/updates #{repo['components']}\n"
      sources.concat "deb-src http://security.debian.org/ #{repo['release']}/updates #{repo['components']}\n\n"
    elsif @node.is_ubuntu?
      sources.concat "deb http://security.ubuntu.com/ubuntu/ #{repo['release']}-security #{repo['components']}\n"
      sources.concat "deb-src http://security.ubuntu.com/ubuntu/ #{repo['release']}-security #{repo['components']}\n\n"
    end
    
    # updates
    sources.concat "deb #{repo['url']} #{repo['release']}-updates #{repo['components']}\n"
    sources.concat "deb-src #{repo['url']} #{repo['release']}-updates #{repo['components']}\n\n"
    
    # proposed
    if @node.is_ubuntu?
      sources.concat "deb #{repo['url']} #{repo['release']}-proposed #{repo['components']}\n"
      sources.concat "deb-src #{repo['url']} #{repo['release']}-proposed #{repo['components']}\n\n"
    end
    
    # backports is enabled per default in ubuntu oneiric
    if @node.is_ubuntu?
      sources.concat "deb #{repo['url']} #{repo['release']}-backports #{repo['components']}\n"
      sources.concat "deb-src #{repo['url']} #{repo['release']}-backports #{repo['components']}\n\n"
    end

    sources
  end
  
  def generate_repo repo
    # add url to sources.list
    sources = ''
    sources.concat "deb #{repo['url']} #{repo['release']} #{repo['components']}\n" if repo['binary']
    sources.concat "deb-src #{repo['url']} #{repo['release']} #{repo['components']}\n" if repo['source']
    sources
  end
  
  def add_repo_key name, repo
    # add the repository key
    if repo['key']
      ::Dust.print_msg "adding #{name} repository key"

      # if the key is a .deb, download and install it
      if repo['key'].match /\.deb$/
        ret = @node.exec 'mktemp --tmpdir dust.XXXXXXXXXX'
        if ret[:exit_code] != 0
          puts
          ::Dust.print_failed 'could not create temporary file on server'
          return false
        end

        tmpfile = ret[:stdout].chomp

        ::Dust.print_result @node.exec("wget -q -O #{tmpfile} '#{repo['key']}' && dpkg -i #{tmpfile}")[:exit_code]

      # if not, just download and add the key
      else
        ::Dust.print_result @node.exec("wget -q -O- '#{repo['key']}' |apt-key add -")[:exit_code]
      end
    end
  end
end
