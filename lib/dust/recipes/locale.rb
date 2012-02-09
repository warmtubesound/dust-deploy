class Locale < Recipe
  desc 'locale:deploy', 'configures system locale'
  def deploy 
    # ubuntu needs a proper language pack
    language = @config.split('_').first
    @node.install_package "language-pack-#{language}-base" if @node.is_ubuntu?
    
    if @node.uses_apt?
      ::Dust.print_msg "setting locale to '#{@config}'"
      @node.write '/etc/default/locale', "LANGUAGE=#{@config}\nLANG=#{@config}\nLC_ALL=#{@config}\nLC_CTYPE=#{@config}\n", :quiet => true
      ::Dust.print_ok
    elsif @node.uses_rpm?
      ::Dust.print_msg "setting locale to '#{@config}'"
      @node.write '/etc/sysconfig/i18n', "LANG=\"#{@config}\"\nLC_ALL=\"#{@config}\"\nSYSFONT=\"latarcyrheb-sun16\"\n", :quiet => true
      ::Dust.print_ok
    else
      ::Dust.print_failed 'os not supported'
    end
  end
  
  desc 'locale:status', 'shows current locale'
  def status
    ::Dust.print_msg 'getting current locale'

    if @node.uses_apt?
      ret = @node.exec 'cat /etc/default/locale'
    elsif @node.uses_rpm?
      ret = @node.exec 'cat /etc/sysconfig/i18n'
    else
      return ::Dust.print_failed
    end
    
    ::Dust.print_result ret[:exit_code]
    ::Dust.print_ret ret
  end  
end
