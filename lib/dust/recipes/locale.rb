class Locale < Thor
  desc 'locale:deploy', 'configures system locale'
  def deploy node, locale, options
    if node.uses_apt? :quiet => true
      ::Dust.print_msg "setting locale to '#{locale}'"
      node.write '/etc/default/locale', "LANGUAGE=#{locale}\nLANG=#{locale}\nLC_ALL=#{locale}\nLC_CTYPE=#{locale}\n", :quiet => true
      ::Dust.print_ok
    elsif node.uses_rpm? :quiet => true
      ::Dust.print_msg "setting locale to '#{locale}'"
      node.write '/etc/sysconfig/i18n', "LANG=\"#{locale}\"\nLC_ALL=\"#{locale}\"\nSYSFONT=\"latarcyrheb-sun16\"\n", :quiet => true
      ::Dust.print_ok
    else
      ::Dust.print_failed 'os not supported'
    end
  end
end

