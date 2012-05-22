class Locale < Recipe
  desc 'locale:deploy', 'configures system locale'
  def deploy
    # ubuntu needs a proper language pack
    language = @config.split('_').first
    @node.install_package "language-pack-#{language}-base" if @node.is_ubuntu?

    if @node.uses_apt?
      msg = @node.messages.add("setting locale to '#{@config}'")
      @node.write '/etc/default/locale', "LANGUAGE=#{@config}\nLANG=#{@config}\nLC_ALL=#{@config}\nLC_CTYPE=#{@config}\n", :quiet => true
      msg.ok
    elsif @node.uses_rpm?
      msg = @node.messages.add("setting locale to '#{@config}'")
      @node.write '/etc/sysconfig/i18n', "LANG=\"#{@config}\"\nLC_ALL=\"#{@config}\"\nSYSFONT=\"latarcyrheb-sun16\"\n", :quiet => true
      msg.ok
    else
      @node.message.add('os not supported').failed
    end
  end

  desc 'locale:status', 'shows current locale'
  def status
    msg = @node.messages.add('getting current locale')

    if @node.uses_apt?
      ret = @node.exec 'cat /etc/default/locale'
    elsif @node.uses_rpm?
      ret = @node.exec 'cat /etc/sysconfig/i18n'
    else
      return msg.failed
    end

    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end
end
