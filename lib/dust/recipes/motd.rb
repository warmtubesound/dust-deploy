require 'erb'

class Motd < Recipe
  desc 'motd:deploy', 'creates message of the day'
  def deploy
    # configure node using erb template
    template = ERB.new File.read("#{@template_path}/motd.erb"), nil, '%<>'
    @node.write '/etc/motd', template.result(binding)
  end
end
