class RcLocal < Recipe
  desc 'rc_local:deploy', 'configures custom startup script'
  def deploy

    if @node.uses_apt?
      @node.messages.add("configuring custom startup script\n")

      rc = ''
      @config.to_array.each do |cmd|
        msg = @node.messages.add("adding command: #{cmd}", :indent => 2)
        rc << "#{cmd}\n"
        msg.ok
      end
      rc << "\nexit 0\n"

      @node.write '/etc/rc.local', rc
      @node.chown 'root:root', '/etc/rc.local'
      @node.chmod '755', '/etc/rc.local'
    else
      @node.messages.add('os not supported').failed
    end
  end

  desc 'rc_local:status', 'shows current /etc/rc.local'
  def status
    msg = @node.messages.add('getting /etc/rc.local')
    ret = @node.exec 'cat /etc/rc.local'
    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end
end
