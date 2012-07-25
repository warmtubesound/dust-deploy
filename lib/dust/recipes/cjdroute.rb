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
    # return unless make_clean if @options.restart?

    # compiling action
    return unless run_make

    # create the config file and place it into etc_dir
    return unless generate_config

    if options.restart?
      stop_cjdroute

      # copy binary
      return unless @node.mkdir @config['bin_dir']
      return unless @node.cp "#{@config['build_dir']}/build/cjdroute", "#{@config['bin_dir']}/cjdroute"

      start_cjdroute
    end
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

  def public_peers
    # list of public peers, taken from https://wiki.projectmeshnet.org/Public_peers
    {
      # greys nodes
      '199.180.252.227:19071' => {
        'password' => 'public_JFh4rX0R1jm6a7eKWCzD',
        'publicKey' => '425bcpr9ns0jpuh9ffx1lbbktkd3tpln16jzs9sgbjdkvfg25zv0.k'
      },

      '80.83.121.61:19071' => {
        'password' => 'public_2bHnV12c5HRgKddJ1ebv',
        'publicKey' => 'n5502gtrr9zhj1m0lxm151fqd5mctw68hp64m61dj1mx7w7kvr30.k'
      },

      # derps nodes 
      '173.255.219.67:10000' => {
        'password' => 'null',
        'publicKey' => 'lj52930v1vmg3jqyb399us501svntt499bvgk0c1fud4pmy42gj0.k'
      },

      '96.126.112.124:10000' => {
        'password' => 'null',
        'publicKey' => '7zy1gb9bw4xp82kjvh66w01jdgh6y3lk7cfnl0pgb0xnn26b2jn0.k'
      },

      # rainfly x
      '76.105.229.241:13982' => {
        'password' => 'general_public_1985',
        'publicKey' => '7pu8nlqphgd1bux9sdpjg0c104217r3b3m1bvmdtbn7uwcj5cky0.k'
      },

      #  ds500ss 
      '87.208.234.24:28078' => {
        'password' => 'freedomnetsrai9yah4Kic5Kojah5que4xoCh',
        'publicKey' => 'qb426vh42usw995jy60ll6rtslguv1ylpvwp44ymzky6f0u5qvq0.k'
      },

      # Dans nodes
      '199.83.100.24:41902' => {
        'password' => 'znuhtpf005705tp8snzbywynm6',
        'publicKey' => 'xltnfur6xh2n36g79y1qpht910c13sq7lb049662x7trfx3gf190.k'
      },

      '173.192.138.43:26099' => {
        'password' => 'fjhgf77nsnsp8mrkvyxbwj5jw0',
        'publicKey' => 'bzmd25v05dctt77nqlgl8rxm24g0q8hwlkkcc64ss7pybbx2ndg0.k'
      },

      '74.221.208.153:51674' => {
        'password' => 'jljwnfutfpt1nz3yjsj0dscpf7',
        'publicKey' => '8hgr62ylugxjyyhxkz254qtz60p781kbswmhhywtbb5rpzc5lxj0.k'
      }
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

      msg = @node.messages.add('pulling latest changes from repository')
      ret = @node.exec("cd #{@config['build_dir']}; git pull", :live => true)[:exit_code]
      return unless msg.parse_result(ret)

    else
      # create build directory
      unless @node.mkdir @config['build_dir']
        return @node.messages.add("couldn't create build directory #{@config['build_dir']}").failed
      end

      # git clone cjdns repository
      msg = @node.messages.add("cloning cjdns repository into #{@config['build_dir']}")
      ret = @node.exec("git clone #{@config['git_repo']} -b #{@config['git_branch']} #{@config['build_dir']}", :live => true)
      return unless msg.parse_result(ret[:exit_code])
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
    msg.parse_result(@node.exec("rm -rf #{@config['build_dir']}/build")[:exit_code])
  end

  def run_make
    msg = @node.messages.add('compiling cjdns')
    msg.parse_result(@node.exec("export Log_LEVEL=#{@config['loglevel']}; cd #{@config['build_dir']}; ./do", :live => true)[:exit_code])
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

    # add some public peers, so we can get started directly
    msg = @node.messages.add('adding public peers', :indent => 2)
    cjdroute_conf['interfaces']['UDPInterface']['connectTo'] = public_peers
    msg.ok

    # exchange tun0 with configured tun device
    cjdroute_conf['router']['interface']['tunDevice'] = @config['tun']

    return false unless @node.mkdir @config['etc_dir']
    return @node.write "#{@config['etc_dir']}/cjdroute.conf", JSON.pretty_generate(cjdroute_conf)
  end

  # kill any cjdroute processes that might be running
  def stop_cjdroute
    msg = @node.messages.add('stopping cjdroute')
    msg.parse_result(@node.exec('killall cjdroute')[:exit_code])

    msg = @node.messages.add('waiting 2 seconds for cjdroute to finish')
    sleep 2
    msg.ok
  end

  # fire up cjdroute
  def start_cjdroute
    msg = @node.messages.add('fireing up cjdroute')
    msg.parse_result(@node.exec("nohup #{@config['bin_dir']}/cjdroute < #{@config['etc_dir']}/cjdroute.conf &> /dev/null &")[:exit_code])
  end
end
