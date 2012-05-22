require 'base64'

class Pacemaker < Recipe
  
  desc 'pacemaker:deploy', 'installs and configures corosync/pacemaker'
  def deploy 
    # this recipe is only tested with ubuntu
    return unless @node.uses_apt?
    return unless @node.install_package 'pacemaker'

    # return if no authkey is given
    unless @config['authkey']
      return ::Dust.print_failed 'no authkey given. generate it using "corosync-keygen" ' +
                                 'and convert it to base64 using "base64 -w0 /etc/corosync/authkey"'
    end

    @node.collect_facts
    
    # set defaults
    @config['interface'] ||= 'eth0'
    @config['mcastaddr'] ||= '226.13.37.1'
    @config['mcastport'] ||= 5405

    # set bindnetaddr to the ip address of @config['interface']
    # unless it is specified manually in node config
    @config['bindnetaddr'] ||= @node["ipaddress_#{@config['interface']}"]

    # decode base64 authkey
    @node.write '/etc/corosync/authkey', Base64.decode64(@config['authkey'])
    @node.deploy_file "#{@template_path}/corosync.conf", '/etc/corosync/corosync.conf', :binding => binding
    
    # not restarting automatically, because it provokes switching of ha services
    #@node.restart_service 'corosync' if @options.restart
  end
  
  desc 'pacemaker:status', 'shows status of pacemaker/corosync cluster'
  def status
    msg = @node.messages.add('running crm_mon')
    ret = @node.exec 'crm_mon -1'
    msg.parse_result(ret[:exit_code])
    msg.print_output(ret)
  end 
end
