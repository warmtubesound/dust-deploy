class Sysctl < Recipe
  desc 'sysctl:deploy', 'configures sysctl'
  def deploy
    # only debian derivatives are supported at the moment, since we need support for /etc/sysctl.d/
    return ::Dust.print_warning 'sysctl configuration not supported for your linux distribution' unless @node.uses_apt?
    
    ::Dust.print_msg "setting sysctl keys\n"
    
    sysctl_conf = ''
    @config.each do |key, value|
      ::Dust.print_msg "setting #{key} to: #{value}", :indent => 2
      ::Dust.print_result @node.exec("sysctl -w #{key}=#{value}")[:exit_code]
      
      sysctl_conf.concat "#{key} = #{value}\n"
    end
    
    ::Dust.print_msg 'saving settings to /etc/sysctl.d/10-dust.conf', :indent => 2
    ::Dust.print_result @node.write("/etc/sysctl.d/10-dust.conf", sysctl_conf, :quiet => true)
  end
end