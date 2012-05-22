class Debsecan < Recipe
  desc 'debsecan:deploy', 'installs and configures debian security package "debsecan"'
  def deploy
    @node.collect_facts

    if @node.is_os? ['ubuntu', 'debian']
      @node.install_package 'debsecan'

      msg = @node.messages.add('configuring debsecan')

      # if config is simply set to "true", use defaults
      config = {} unless config.is_a? Hash

      # setting default config variables (unless already set)
      config['report'] ||= false
      config['mailto'] ||= 'root'
      config['source'] ||= ''

      config_file = ''

      # configures whether daily reports are sent
      config_file << "# If true, enable daily reports, sent by email.\n" +
                     "REPORT=#{config['report'].to_s}\n\n"

      # configures the suite
      config_file << "# For better reporting, specify the correct suite here, using the code\n" +
                     "# name (that is, \"sid\" instead of \"unstable\").\n" +
                     "SUITE=#{@node['lsbdistcodename']}\n\n"

      # which user gets the reports?
      config_file << "# Mail address to which reports are sent.\n" +
                     "MAILTO=#{config['mailto']}\n\n"

      # set vulnerability source
      config_file << "# The URL from which vulnerability data is downloaded.  Empty for the\n" +
                     "# built-in default.\n" +
                     "SOURCE=#{config['source']}\n\n"

      @node.write '/etc/default/debsecan', config_file, :quiet => true
      msg.ok
    else
      msg.failed('os not supported')
    end
  end
end
