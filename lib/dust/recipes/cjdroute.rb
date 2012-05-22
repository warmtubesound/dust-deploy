require 'json'

class Cjdroute< Recipe
  desc 'cjdroute:deploy', 'installs / updates cjdns'
  def deploy
    # apply default configuration
    @config = default_config.merge @config

    return unless install_dependencies
    return unless get_latest_version

    # clean up building directory, if --restart is given
    # using --restart, since there's no --cleanup
    return unless make_clean if @options.restart?
    return unless @node.mkdir "#{@config['build_dir']}/build"

    # compiling action
    return unless run_make

    stop_cjdroute

    # copy binary
    return unless @node.mkdir @config['bin_dir']
    return unless @node.cp "#{@config['build_dir']}/build/cjdroute", "#{@config['bin_dir']}/cjdroute"

    # create the config file and place it into etc_dir
    return unless generate_config

    start_cjdroute
  end


  private
  def default_config
    {
      'git_repo' => 'git://github.com/cjdelisle/cjdns.git',
      'git_branch' => 'master',
      'build_dir' => '/tmp/cjdns-tmp',
      'bin_dir' => '/usr/local/bin',
      'etc_dir' => '/etc/cjdns/',
      'tun' => 'cjdroute0',
      'loglevel' => 'INFO'
    }
  end

  # installs cmake, git and other building tools needed
  def install_dependencies
    @node.messages.add("installing build dependencies\n")

    return false unless @node.install_package 'cmake', :indent => 2

    # check cmake version
    ret = @node.exec 'cmake --version'
    ver = ret[:stdout].match(/2.[0-9]/)[0].to_f
    return @node.messages.add('cjdroute requires cmake 2.8 or higher').failed if ver < 2.8


    if @node.uses_apt?
      return false unless @node.install_package 'git-core', :indent => 2
      return false unless @node.install_package 'build-essential', :indent => 2
      return false unless @node.install_package 'psmisc', :indent => 2
      return false unless @node.install_package 'coreutils', :indent => 2
    else
      return false unless @node.install_package 'git', :indent => 2
      return false unless @node.install_package 'gcc', :indent => 2
      return false unless @node.install_package 'make', :indent => 2
    end

    true
  end

  # gets/updates latest version from cjdns git repository
  def get_latest_version
    if @node.dir_exists? @config['build_dir'], :quiet => true

      # check if build directory is maintained by git
      unless @node.dir_exists? "#{@config['build_dir']}/.git", :quiet => true
        return @node.messages.add("#{@config['build_dir']} doesn't appear to be a git repository").failed
      end

      # git pull latest changes
      msg = @node.messages.add("checking out branch '#{@config['git_branch']}'")
      ret = @node.exec("cd #{@config['build_dir']}; git checkout #{@config['git_branch']}")[:exit_code]
      return unless msg.parse_result(ret)

      msg = @node.messages.add("pulling latest changes from repository\n")
      ret = @node.exec "cd #{@config['build_dir']}; git pull", :live => true
      return msg.failed('error pulling from git repository') unless ret[:exit_code] == 0

    else
      # create build directory
      unless @node.mkdir @config['build_dir']
        return @node.messages.add("couldn't create build directory #{@config['build_dir']}").failed
      end

      # git clone cjdns repository
      msg = @node.messages.add("cloning cjdns repository into #{@config['build_dir']}\n")
      ret = @node.exec "git clone #{@config['git_repo']} -b #{@config['git_branch']} #{@config['build_dir']}", :live => true
      return msg.failed('error cloning git repository') unless ret[:exit_code] == 0
    end

    # reset to the wanted commit if given
    if @config['commit']
      msg = @node.messages.add("resetting to commit: #{@config['commit']}")
      msg.parse_result(@node.exec("cd #{@config['build_dir']}; git reset --hard #{@config['commit']}")[:exit_code])
    end

    true
  end

  # remove and recreate building directory
  def make_clean
    msg = @node.messages.add('cleaning up')
    return false unless msg.parse_result(@node.exec("rm -rf #{@config['build_dir']}/build")[:exit_code])
    true
  end

  def run_make
    msg = @node.messages.add("compiling cjdns\n")
    ret = @node.exec "export Log_LEVEL=#{@config['loglevel']}; cd #{@config['build_dir']}; ./do", :live => true
    return msg.failed('error compiling cjdroute') unless ret[:exit_code] == 0
    true
  end

  # generate cjdroute.conf
  def generate_config
    if @node.file_exists? "#{@config['etc_dir']}/cjdroute.conf", :quiet => true
      @node.messages.add('found a cjdroute.conf, not overwriting').warning
      return true
    end

    msg = @node.messages.add('generating config file')
    ret = @node.exec("#{@config['bin_dir']}/cjdroute --genconf")
    return false unless msg.parse_result(ret[:exit_code])

    # parse generated json
    cjdroute_conf = JSON.parse ret[:stdout]

    # exchange tun0 with configured tun device
    cjdroute_conf['router']['interface']['tunDevice'] = @config['tun']

    return false unless @node.mkdir @config['etc_dir']
    return @node.write "#{@config['etc_dir']}/cjdroute.conf", JSON.pretty_generate(cjdroute_conf)
  end

  # kill any cjdroute processes that might be running
  def stop_cjdroute
    msg = @node.messages.add('stopping cjdroute')
    msg.parse_result(@node.exec('killall cjdroute')[:exit_code])
  end

  # fire up cjdroute
  def start_cjdroute
    sleep 2 # sleep to make sure old cjdroute is dead
    msg = @node.messages.add('fireing up cjdroute')
    msg.parse_result(@node.exec("nohup #{@config['bin_dir']}/cjdroute < #{@config['etc_dir']}/cjdroute.conf &> /dev/null &")[:exit_code])
  end
end
