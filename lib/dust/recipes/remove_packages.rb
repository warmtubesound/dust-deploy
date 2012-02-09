class RemovePackages < Recipe
  desc 'remove_packages:deploy', 'removes packages'
  def deploy
    @config.each do |package| 
      @node.remove_package package
    end
  end
end
