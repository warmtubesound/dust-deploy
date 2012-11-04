class Packages < Recipe
  desc 'packages:deploy', 'installs packages'
  def deploy
    Array(@config).each do |package|
      @node.install_package(package)
    end
  end
end
