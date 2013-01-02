class Skel < Recipe
  desc 'skel:deploy', 'copy default configuration files to users home directory'
  def deploy
    Array(@config).each do |user|
      home = @node.get_home(user)
      unless home
        @node.messages.add("couldn't find home directory for user #{user}").failed
        next
      end

      @node.messages.add("deploying homedir skeleton for #{user}\n")
      Dir["#{@template_path}/.*"].each do |file|
        next unless File.file?(file)
        @node.deploy_file(file, "#{home}/#{File.basename(file)}", { :binding => binding, :indent => 2 })
        @node.chown("#{user}:#{@node.get_gid(user)}", "#{home}/#{File.basename(file)}", :indent => 2)
      end
    end
  end
end
