class Sysctl < Recipe
  desc 'sysctl:deploy', 'configures sysctl'
  def deploy
    # we need support for /etc/sysctl.d/
    unless @node.dir_exists? '/etc/sysctl.d/'
      return @node.messages.add('sysctl configuration not supported for your linux distribution').warning
    end

    # seperate templates from sysctls
    sysctls = @config.clone
    templates = sysctls.delete 'templates'

    # apply template sysctls
    if templates
      templates.to_array.each do |template|
        @node.messages.add("configuring sysctls for template #{template}\n")
        apply template, self.send(template)
      end
    end

    # apply plain sysctls
    @node.messages.add("configuring plain sysctls\n")
    apply 'dust', sysctls
  end


  private

  def apply name, sysctl
    sysctl_conf = ''
    sysctl.each do |key, value|
      msg = @node.messages.add("setting #{key} = #{value}", :indent => 2)
      msg.parse_result(@node.exec("sysctl -w #{key}=#{value}")[:exit_code])
      sysctl_conf << "#{key} = #{value}\n"
    end

    msg = @node.messages.add("saving settings to /etc/sysctl.d/#{name}.conf", :indent => 2)
    msg.parse_result(@node.write("/etc/sysctl.d/#{name}.conf", sysctl_conf, :quiet => true))
  end


  ### templates ###

  # disable allocation of more ram than actually there for postgres
  def postgres
    database.merge 'vm.overcommit_memory' => 2
  end

  # redis complains if vm.overcommit_memory != 1
  def redis
    { 'vm.overcommit_memory' => 1, 'vm.swappiness' => 0 }
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
