class Make < Recipe
  desc 'make:deploy', 'configure, make, make install'
  def deploy 
    # install dependencies (defaults, build-essential | make, gcc)
    @node.install_package 'build-essential'

    # create temporary directory
    ret = @node.exec 'mktemp -d --tmpdir dust_make.XXXXXXXXX'
    return ::Dust.print_failed 'error creating temporary directory' if ret[:exit_code] != 0
    tempdir = ret[:stdout].chomp

    url = 'http://www.securixlive.com/download/barnyard2/barnyard2-1.9.tar.gz'

    if url =~ /\.(tar.gz|tgz)$/
    elsif url.end_with? '.tar.bz2'
    elsif url.end_with? '.zip'
    else
    end

    # if @config['svn']
    # if @config['git']

    # get url, svn, git repository
    # unpack bz2, tgz, zip
   
    # run commands (default [ './configure --prefix=/usr/local/', 'make', 'make install' ]
    # symlink
  end
end
