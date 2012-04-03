class Sysctl < Recipe
  desc 'sysctl:deploy', 'configures sysctl'
  def deploy
    # only debian derivatives are supported at the moment, since we need support for /etc/sysctl.d/
    return ::Dust.print_warning 'sysctl configuration not supported for your linux distribution' unless @node.uses_apt?

    # seperate templates from sysctls
    sysctls = @config.clone
    templates = sysctls.delete 'templates'

    # apply template sysctls
    if templates
      templates.to_array.each do |template|
        ::Dust.print_msg "configuring sysctls for template #{template}\n"
        apply template, self.send(template)
        puts
      end
    end

    # apply plain sysctls
    ::Dust.print_msg "configuring plain sysctls\n"
    apply 'dust', sysctls
  end


  private

  def apply name, sysctl
    sysctl_conf = ''
    sysctl.each do |key, value|
      ::Dust.print_msg "setting #{key} = #{value}", :indent => 2
      ::Dust.print_result @node.exec("sysctl -w #{key}=#{value}")[:exit_code]
      sysctl_conf << "#{key} = #{value}\n"
    end

    ::Dust.print_msg "saving settings to /etc/sysctl.d/10-#{name}.conf", :indent => 2
    ::Dust.print_result @node.write("/etc/sysctl.d/10-#{name}.conf", sysctl_conf, :quiet => true)
  end


  ### templates ###

  # disable allocation of more ram than actually there for postgres
  def postgres
    database.merge 'vm.overcommit_memory' => 2
  end

  def mysql
    database
  end

  # use half of the system memory for shmmax
  # and set shmall according to pagesize
  def database
    @node.collect_facts :quiet => true

    # get pagesize
    pagesize = @node.exec('getconf PAGESIZE')[:stdout].to_i || 4096

    # use half of system memory for shmmax
    shmmax = ::Dust.convert_size(@node['memorysize']) * 1024 / 2
    shmall = shmmax / pagesize

    { 'kernel.shmmax' => shmmax, 'kernel.shmall' => shmall }
  end

end
