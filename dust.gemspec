# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "dust/version"

Gem::Specification.new do |s|
  s.name        = "dust-deploy"
  s.version     = Dust::VERSION
  s.authors     = ["kris kechagia"]
  s.email       = ["kk@rndsec.net"]
  s.homepage    = "https://github.com/kechagia/dust-deploy"
  s.summary     = %q{small server deployment tool for complex environments}
  s.description = %q{when puppet and chef suck because you want to be in control and sprinkle just cannot do enough for you}

  s.rubyforge_project = "dust-deploy"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'net-ssh'
  s.add_runtime_dependency 'net-scp'
  s.add_runtime_dependency 'net-sftp'
  s.add_runtime_dependency 'thor'
  s.add_runtime_dependency 'ipaddress'
  s.add_runtime_dependency 'colorize'
end
