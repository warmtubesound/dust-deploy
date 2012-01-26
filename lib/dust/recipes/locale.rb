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
end

