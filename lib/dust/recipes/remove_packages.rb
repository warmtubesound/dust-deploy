class RemovePackages < Thor
  desc 'remove_packages:deploy', 'removes packages'
  def deploy node, packages, options
    packages.each do |package| 
      node.remove_package package
    end
  end
end

