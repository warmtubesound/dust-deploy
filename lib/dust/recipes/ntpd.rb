class Ntpd < Recipe
  desc 'ntpd:deploy', 'installs and configures ntpd'
  def deploy
    @node.install_package 'ntp'
    
    service = @node.uses_apt? ? 'ntp' : 'ntpd'

    @node.autostart_service service
    @node.restart_service service if options.restart?
  end


  private

end

