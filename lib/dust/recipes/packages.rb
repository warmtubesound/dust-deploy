class Packages < Recipe
  desc 'packages:deploy', 'installs packages'
  def deploy 
    @config.each do |package| 
      @node.install_package package
    end
  end
end
