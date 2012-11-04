require 'dust/server/ssh'
require 'dust/server/osdetect'
require 'dust/server/package'

module Dust
  class Server
    # collect additional system facts using puppets facter
    def collect_facts(options={})
      options = default_options.merge(options)

      # if facts already have been collected, just return
      return true if @node['operatingsystem']

      # check if lsb-release (on apt systems) and facter are installed
      # and install them if not
      if uses_apt? and not package_installed?('lsb-release', :quiet => true)
        install_package('lsb-release', :quiet => false)
      end

      unless package_installed?('facter', :quiet => true)
        return false unless install_package('facter', :quiet => false)
      end

      msg = messages.add("collecting additional system facts (using facter)", options)

      # run facter with -y for yaml output, and merge results into @node
      ret = exec('facter -y')
      @node = YAML.load(ret[:stdout]).merge(@node)

      msg.parse_result(ret[:exit_code])
    end
  end
end
