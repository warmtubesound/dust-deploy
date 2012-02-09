class RcLocal < Recipe
  desc 'rc_local:deploy', 'configures custom startup script'
  def deploy

    if @node.uses_apt?
      ::Dust.print_msg "configuring custom startup script\n"

      rc = ''
      @config.each do |cmd|
        ::Dust.print_msg "adding command: #{cmd}", :indent => 2
        rc += "#{cmd}\n"
        ::Dust.print_ok
      end
      rc += "\nexit 0\n"

      @node.write '/etc/rc.local', rc
      @node.chown 'root:root', '/etc/rc.local'
      @node.chmod '755', '/etc/rc.local'
    else
      ::Dust.print_failed 'os not supported'
    end
  end
  
  desc 'rc_local:status', 'shows current /etc/rc.local'
  def status
    ::Dust.print_msg 'getting /etc/rc.local'
    ret = @node.exec 'cat /etc/rc.local'
    ::Dust.print_result ret[:exit_code]
    ::Dust.print_ret ret
  end
end
