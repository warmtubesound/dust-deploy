class Repositories < Recipe
  desc 'repositories:deploy', 'configures package management repositories (aptitude, yum)'
  def deploy
    return unless @node.collect_facts

    delete_old_repositories
    deploy_repositories

    # fetch new stuff
    @node.update_repos if options.restart? or options.reload?
  end


  private

  # deletes all .list files under /etc/apt/sources.list.d
  def delete_old_repositories
    msg = @node.messages.add('deleting old repositories')
    @node.rm('/etc/apt/sources.list.d/*.list', :quiet => true) if @node.uses_apt?
    msg.ok
  end

  def deploy_repositories
    @config.each do |name, repo|

      # if repo is present but not a hash use defaults
      repo = {} unless repo.is_a? Hash

      merge_with_default_settings(repo)

      # the default repository in /etc/apt/sources.list (debian)
      if name == 'default'
        msg = @node.messages.add('deploying default repository')
        sources = generate_default_repo(repo)
        msg.parse_result(@node.write('/etc/apt/sources.list', sources, :quiet => true))
      else
        if repo['ppa']
          @node.messages.add("adding ppa repository '#{name}'\n")
          add_ppa(repo)
        else
          msg = @node.messages.add("adding repository '#{name}' to sources")
          sources = generate_repo(repo)
          msg.parse_result(@node.write("/etc/apt/sources.list.d/#{name}.list", sources, :quiet => true))
          add_repo_key(name, repo)
        end
      end
    end
  end

  # merge repo configuration with default settings
  def merge_with_default_settings(repo)
    # setting defaults
    repo['url'] ||= 'http://ftp.debian.org/debian/' if @node.is_debian?
    repo['url'] ||= 'http://archive.ubuntu.com/ubuntu/' if @node.is_ubuntu?

    repo['release'] ||= @node['lsbdistcodename']
    repo['components'] ||= 'main'

    # ||= doesn't work for booleans
    repo['source'] = repo['source'].nil? ? true : repo['source']
    repo['binary'] = repo['binary'].nil? ? true : repo['binary']
  end

  def generate_default_repo(repo)
    sources = ''
    sources << "deb #{repo['url']} #{repo['release']} #{repo['components']}\n"
    sources << "deb-src #{repo['url']} #{repo['release']} #{repo['components']}\n\n"

    # security
    if @node.is_debian?
      sources << "deb http://security.debian.org/ #{repo['release']}/updates #{repo['components']}\n"
      sources << "deb-src http://security.debian.org/ #{repo['release']}/updates #{repo['components']}\n\n"
    elsif @node.is_ubuntu?
      sources << "deb http://security.ubuntu.com/ubuntu/ #{repo['release']}-security #{repo['components']}\n"
      sources << "deb-src http://security.ubuntu.com/ubuntu/ #{repo['release']}-security #{repo['components']}\n\n"
    end

    # updates
    sources << "deb #{repo['url']} #{repo['release']}-updates #{repo['components']}\n"
    sources << "deb-src #{repo['url']} #{repo['release']}-updates #{repo['components']}\n\n"

    # proposed
    if @node.is_ubuntu?
      sources << "deb #{repo['url']} #{repo['release']}-proposed #{repo['components']}\n"
      sources << "deb-src #{repo['url']} #{repo['release']}-proposed #{repo['components']}\n\n"
    end

    # backports is enabled per default in ubuntu oneiric
    if @node.is_ubuntu?
      sources << "deb #{repo['url']} #{repo['release']}-backports #{repo['components']}\n"
      sources << "deb-src #{repo['url']} #{repo['release']}-backports #{repo['components']}\n\n"
    end

    sources
  end

  def add_ppa(repo)
    return false unless @node.install_package('python-software-properties', :indent => 2)
    msg = @node.messages.add('running add-apt-repository', :indent => 2)
    cmd = "add-apt-repository -y ppa:#{repo['ppa']}"
    if repo['keyserver']
      @node.messages.add("using custom keyserver '#{repo['keyserver']}'").ok
      cmd << " -k #{repo['keyserver']}"
    end
    msg.parse_result(@node.exec(cmd)[:exit_code])
  end

  def generate_repo(repo)
    # add url to sources.list
    sources = ''
    repo['release'].to_array.each do |release|
      sources << "deb #{repo['url']} #{release} #{repo['components']}\n" if repo['binary']
      sources << "deb-src #{repo['url']} #{release} #{repo['components']}\n" if repo['source']
    end
    sources
  end

  def add_repo_key(name, repo)
    # add the repository key
    if repo['key']
      msg = @node.messages.add("adding #{name} repository key")

      # if the key is a .deb, download and install it
      if repo['key'].match /\.deb$/
        ret = @node.exec('mktemp --tmpdir dust.XXXXXXXXXX')
        if ret[:exit_code] != 0
          msg.failed('could not create temporary file on server')
          return false
        end

        tmpfile = ret[:stdout].chomp

        msg.parse_result(@node.exec("wget -q -O #{tmpfile} '#{repo['key']}' && dpkg -i #{tmpfile}")[:exit_code])

      # if not, just download and add the key
      else
        msg.parse_result(@node.exec("wget -q -O- '#{repo['key']}' |apt-key add -")[:exit_code])
      end
    end
  end
end
