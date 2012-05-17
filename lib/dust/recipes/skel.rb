class Skel < Recipe
  desc 'skel:deploy', 'copy default configuration files to users home directory'
  def deploy 
    @config.to_array.each do |user|
      @node.messages.add("deploying homedir skeleton for #{user}\n")
      Dir["#{@template_path}/.*"].each do |file|
        next unless File.file? file
        @node.deploy_file file, "/#{@node.get_home user}/#{File.basename file}", { :binding => binding, :indent => 2 }
      end
      puts
    end
  end
end
