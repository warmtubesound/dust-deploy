class Newrelic < Recipe
  desc 'newrelic:deploy', 'installs and configures newrelic system monitoring'
  def deploy
    return @node.messages.add('no key specified').failed unless @config

    unless @node.install_package('newrelic-sysmond')
      @node.messages.add('installing newrelic monitoring daemon failed, did you setup the newrelic repositories?').failed
      return
    end

    msg = @node.messages.add('configuring new relic server monitoring tool')
    return unless msg.parse_result(@node.exec("nrsysmond-config --set ssl=true license_key=#{@config}")[:exit_code])

    @node.restart_service 'newrelic-sysmond' if options.restart?
  end
end
