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
    return unless run_cmake
    return unless run_make

    stop_cjdroute

    # copy binary
    return unless @node.mkdir @config['bin_dir']
    return unless @node.cp "#{@config['build_dir']}/build/cjdroute", "#{@config['bin_dir']}/cjdroute"

    # create the config file and place it into etc_dir
    return unless generate_config

    # create the tuntap interface
    return unless create_tuntap

    # add route for cjdns network
    return unless add_route

    start_cjdroute
  end


  private
  def default_config
    { 
      'git_repo' => 'git://github.com/cjdelisle/cjdns.git',
      'build_dir' => '/tmp/cjdns-tmp',
      'bin_dir' => '/usr/local/bin',
      'etc_dir' => '/etc/cjdns/',
      'tun' => 'cjdroute0',
    }
  end

  def public_peers
    # list of public peers, taken from https://wiki.projectmeshnet.org/Public_peers
    {
      # derps nodes 
      '173.255.219.67:10000' => {
        'password' => 'null',
        'publicKey' => 'lj52930v1vmg3jqyb399us501svntt499bvgk0c1fud4pmy42gj0.k',
        'trust' => 5000,
        'authType' => 1
      },

      '96.126.112.124:10000' => {
        'password' => 'null',
        'publicKey' => '7zy1gb9bw4xp82kjvh66w01jdgh6y3lk7cfnl0pgb0xnn26b2jn0.k',
        'trust' => 5000,
        'authType' => 1
      },

      # rainfly x
      '76.105.229.241:13982' => {
        'password' => 'general_public_1985',
        'publicKey' => '7pu8nlqphgd1bux9sdpjg0c104217r3b3m1bvmdtbn7uwcj5cky0.k',
        'trust' => 5000,
        'authType' => 1
      },

      # grey
      '199.180.252.227:19081' => {
        'password' => 'public_7h4yTNEnRSEUvfFLtsM3',
        'publicKey' => 'z5htnv9jsj85b64cf61lbnl3dmqk5lpv3vxtz9g1jqlvb3b30b90.k',
        'trust' => 5000,
        'authType' => 1
      },

      # waaghals, expires 01.05.2012
      '37.34.49.56:61530' => {
        'password' => 'public-expires-may-ghsfYATSvjh65SFgd',
        'publicKey' => 'jcvn5bvvfkxt3pmhj8bqzm6y20unc7cd5vuyhg01tmbh7bvswqq0.k',
        'trust' => 5000,
        'authType' => 1
      }
    }
  end

  # installs cmake, git and other building tools needed
  def install_dependencies
    ::Dust.print_msg "installing build dependencies\n"

    return false unless @node.install_package 'cmake', :indent => 2

    # check cmake version
    ret = @node.exec 'cmake --version'
    ver = ret[:stdout].match(/2.[0-9]/)[0].to_f
    return ::Dust.print_failed 'cjdroute requires cmake 2.8 or higher' if ver < 2.8


    if @node.uses_apt?
      return false unless @node.install_package 'git-core', :indent => 2
      return false unless @node.install_package 'build-essential', :indent => 2
      return false unless @node.install_package 'coreutils', :indent => 2
    elsif @node.uses_rpm?
      return false unless @node.install_package 'git', :indent => 2
      return false unless @node.install_package 'gcc', :indent => 2
      return false unless @node.install_package 'make', :indent => 2
    else 
      return ::Dust.print_failed 'sorry, your os is not supported by this script'
    end

    puts
    true
  end

  # gets/updates latest version from cjdns git repository
  def get_latest_version
    if @node.dir_exists? @config['build_dir'], :quiet => true

      # check if build directory is maintained by git
      unless @node.dir_exists? "#{@config['build_dir']}/.git", :quiet => true
        return ::Dust.print_failed "#{@config['build_dir']} doesn't appear to be a git repository"
      end

      # git pull latest changes
      ::Dust.print_msg "pulling latest changes from repository\n"
      ret = @node.exec "cd #{@config['build_dir']}; git pull", :live => true
      return ::Dust.print_failed 'error pulling from git repository' unless ret[:exit_code] == 0

    else
      # create build directory
      unless @node.mkdir @config['build_dir']
        return ::Dust.print_failed "couldn't create build directory #{@config['build_dir']}"
      end

      # git clone cjdns repository
      ::Dust.print_msg "cloning cjdns repository into #{@config['build_dir']}\n"
      ret = @node.exec "git clone #{@config['git_repo']} #{@config['build_dir']}", :live => true
      return ::Dust.print_failed 'error cloning git repository' unless ret[:exit_code] == 0
    end

    puts
    true
  end

  # remove and recreate building directory
  def make_clean
    ::Dust.print_msg 'cleaning up'
    return false unless ::Dust.print_result @node.exec("rm -rf #{@config['build_dir']}/build")[:exit_code]
    true
  end


  def run_cmake
    ::Dust.print_msg "running cmake\n"
    ret = @node.exec "cd #{@config['build_dir']}/build; cmake ..", :live => true
    return ::Dust.print_failed 'error running cmake' unless ret[:exit_code] == 0
    true
  end

  def run_make
    ::Dust.print_msg "compiling cjdns\n"
    ret = @node.exec "cd #{@config['build_dir']}/build; make", :live => true
    return ::Dust.print_failed 'error compiling cjdroute' unless ret[:exit_code] == 0
    true
  end

  # generate cjdroute.conf
  def generate_config
    if @node.file_exists? "#{@config['etc_dir']}/cjdroute.conf", :quiet => true
      ::Dust.print_warning 'found a cjdroute.conf, not overwriting'
      return true
    end
    
    ::Dust.print_msg 'generating config file'
    ret = @node.exec("#{@config['bin_dir']}/cjdroute --genconf")
    return false unless ::Dust.print_result ret[:exit_code]

    # parse generated json
    cjdroute_conf = JSON.parse ret[:stdout]

    # add some public peers, so we can get started directly
    ::Dust.print_msg 'adding public peers', :indent => 2
    cjdroute_conf['interfaces']['UDPInterface']['connectTo'] = public_peers
    ::Dust.print_ok

    # exchange tun0 with configured tun device
    cjdroute_conf['router']['interface']['tunDevice'] = @config['tun']

    return false unless @node.mkdir @config['etc_dir']
    return @node.write "#{@config['etc_dir']}/cjdroute.conf", JSON.pretty_generate(cjdroute_conf)
  end

  # creates the cjdroute tuntap device
  def create_tuntap
    unless @node.exec("/sbin/ip tuntap list |grep #{@config['tun']}")[:exit_code] == 0
      ::Dust.print_msg "creating tun interface #{@config['tun']}"
      return false unless ::Dust.print_result @node.exec("/sbin/ip tuntap add mode tun dev #{@config['tun']}")[:exit_code]
    else
      ::Dust.print_msg "tun interface #{@config['tun']} already exists, flushing ip addresses"
      ::Dust.print_result @node.exec("ip addr flush dev #{@config['tun']}")[:exit_code]
    end

    true
  end

  # set the route for the cjdns network
  def add_route
    ::Dust.print_msg 'getting routing information'
    ret = @node.exec "#{@config['bin_dir']}/cjdroute --getcmds < #{@config['etc_dir']}/cjdroute.conf"
    return false unless ::Dust.print_result ret[:exit_code]

    ::Dust.print_msg 'applying cjdns routes'
    ::Dust.print_result @node.exec(ret[:stdout])[:exit_code]
  end

  # kill any cjdroute processes that might be running
  def stop_cjdroute
    ::Dust.print_msg 'stopping cjdroute'
    pids = @node.exec("ps ax |grep cjdroute |grep -v grep |awk '{print $1}'")[:stdout]
    pids.each_line { |pid| @node.exec "kill #{pid}" }
    ::Dust.print_ok
  end

  # fire up cjdroute
  def start_cjdroute
    ::Dust.print_msg 'fireing up cjdroute'
    ::Dust.print_result @node.exec("nohup #{@config['bin_dir']}/cjdroute < #{@config['etc_dir']}/cjdroute.conf &> /dev/null &")[:exit_code]
  end
end
