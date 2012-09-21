class Puppet < Recipe
  desc 'puppet:deploy', 'installs puppet and runs specified manifsts'
  def deploy
    return @node.messages.add('could not install puppet').failed unless @node.install_package('puppet')

    # generate temporary directory, where to put the manifests and modules
    tmpdir = @node.mktemp(:type => 'directory')

    @config.each do |manifest, arguments|

      unless File.exists?("#{@template_path}/#{manifest}")
        @node.messages.add("couldn't find puppet module '#{manifest}").failed
        next
      end

      @node.scp("#{@template_path}/#{manifest}", "#{tmpdir}/#{manifest}")

      # if manifest is just a simple file, exec
      if manifest =~ /\.pp$/
        msg = @node.messages.add("applying puppet manifest '#{manifest}'")
        ret = @node.exec("puppet apply -e \"$(cat #{tmpdir}/#{manifest})\"", :live => true)

      # if it's a module, include it
      else
        msg = @node.messages.add("applying puppet module '#{manifest}'")
        ret = @node.exec("puppet apply -e \"include #{manifest}\" --modulepath #{tmpdir}", :live => true)
      end

      msg.parse_result(ret[:exit_code])


      # TODO
      # either remove manifests, or make them run periodically using a cronjob
    end
  end

  desc 'puppet:status', 'shows puppet status'
  def status
  end
end
