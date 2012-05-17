class Ntpd < Recipe
  desc 'ntpd:deploy', 'installs and configures ntpd'
  def deploy
    # warn if other ntp package is installed
    [ 'openntpd', 'chrony' ].each do |package|
      if @node.package_installed? package, :quiet => true
        @node.messages.add("#{package} installed, might conflict with ntpd, might be deleted").warning
      end
    end

    @node.install_package 'ntp'

    service = @node.uses_apt? ? 'ntp' : 'ntpd'

    @node.autostart_service service
    @node.restart_service service if options.restart?
  end
end

