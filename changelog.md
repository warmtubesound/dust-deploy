Changelog
=============

0.9.1
------------

-  ruby_rvm now installs dependencies on rpm systems as well, was tested with centos/scientificlinux 6.1


0.9.0
------------

-  @node.exec now supports a :as_user => username argument, and then executes the command as the specified user
-  fixes a bug where @noed.uses_* methods wherent properly cached
-  sudo prompt is not displayed anymore when using :live => true
-  duplicity recipe and cronjob example now inverts the --exclude and --include order. this is more what you probably want. 
   BE CAREFUL: you may have to adapt your cronjob.erb for duplicity. have a look at the updated example

-  adds ruby_rvm recipe, you can now maintain your ruby version with dust and rvm.

   recipes:
     ruby_rvm:
       # installs a specified ruby version using rvm for this user
       myuser: '1.9.3-p125'


0.8.3
------------

-  cjdroute recipe fixes (manually adding rules not necessary anymore)
-  small bugfixes


0.8.2
------------

-  cjdroute recipe fixes


0.8.1
------------

-  introduces @node.cp and @node.mv
-  adds cjdroute recipe: https://github.com/kechagia/dust-deploy/wiki/cjdroute/


0.8.0
------------

-  adds templates support for sysctl recipe (database, mysql and postgres templates are supported)
-  removes automatic sysctl configuration from database recipes (mysql and postgres)
   to preserve the way it was, you have to add the according database template to your sysctl configuration:

    recipes:
      postgres:
        <your postgres configuration here>

      sysctl:
        templates: postgres
        <your sysctl configuration here>


-  iptables: fixes a small issue where custom chains in tables != filter were not cleared correctly
-  iptables: support custom chains now

    recipes:
      iptables:
        input:
          rule_1: { ..., jump: CUSTOM }
        custom:
          custom_1: ...



0.7.6
------------

-  further improvement of ruby1.9 support
-  problem in nginx recipe fixed when using multiple sites
-  adds sysctl recipe

    recipes:
      sysctl:
        net.ipv4.tcp_max_syn_backlog: 1024


0.7.5
------------

-  dust is now compatible with ruby 1.9 again
-  'dust exec' now displays stdout/stderr live


0.7.4
------------

-  node.install_package now repsects options
-  make sure openssh-clients is installed on rpm machines before trying to scp
-  node.exec now supports :live => true option, which displays stdout/stderr live
-  'dust system_update' uses this new live function, so you can now watch the update process live


0.7.3
------------

-  fixes issue in node.get_home (errors when there were two similar usernames or two passwd entries for the same user)


0.7.2
------------

-  fixes small bug in postgres recipe


0.7.1
------------

-  adds logrotate recipe
-  you can now enable recipes using default configuration:
   
    recipes:
      recipe1: true
      recipe2: enabled
      recipe3: false
      recipe4: disabled


0.7.0
------------

-  adds sudo support, you can now connect using an unpriviledged user. needs sudo rights, e.g.: 
   <username> ALL=(ALL) ALL

    hostname: myhost
    port: 22
    user: myuser
    password: mypass # not needed when connecting using ssh keys
    sudo: true


-  adds status command to most recipes (you can now watch the status of current recipes/daemons with 'dust status'
-  node.restart/reload now tries systemd, upstart, sysvconfig and then uses initscript as fallback
-  node.autostart_service now uses systemd on rpm systems (if available), falls back to chkconfig
-  adds node.print_service_status method, used to retrieve daemon status
-  adds new ::Dust.print_ret method, used to print stderr/stdout from node.exec in different colors 
-  mysql recipe now defaults to 0.7 of system ram for innodb buffer size, because 0.8 sometimes lead to oom situations


0.6.2
------------

-  adds redis recipe, you can now maintain your redis configurations with dust as well:

    recipes:
      redis:
        port: 6379
        daemonize: yes

-  the redis recipe also supports the 'status' command
-  fixes hash_check recipe, now works with centos-like machines as well
-  improves mysql recipe: now sets shm sysctls as well (like the postgresql recipe does)
-  small improvements to automatic innodb tuning


0.6.1
------------

-  adds cups_client recipe
-  @node.get_home uses 'getent passwd' now instead of '/etc/passwd'


0.6.0
------------

-  improves postgresql recipe. now accepts every option and tries to automatically configure the settings based on your system ram (unless you specify them manually). you have to change your postgresql coniguration.

    recipes:
      postgres:
        cluster: main
        version: 9.1
        dbuser: 'postgres:postgres'

      postgresql.conf:
        listen_addresses: *
        port: 5432 

      pg_hba.conf:
        - 'local   all         postgres                 trust'


-  improves zabbix_agent recipe. accepts all options as well, no need for erb template anymore. It tries to automatically configure monitoring of adaptec raid controllers, postgres databases and system (security) updates. other UserParameters are configured using an array:

    recipes:
      zabbix_agent:
        Server: zabbix.example.com
        UserParameter:
          - user.parameter,myshellcommand1
          - user.otherparameter,myothershellcommand


-  locale recipe now installs language-base package of selected language on ubuntu nodes
-  postgres recipe now installs postgresql meta package as well on apt systems
-  adds more examples (e.g. an ubuntu template)
-  @node.uses_*? and collect_facts methods now caching result, reducing overhead of repeated statements
-  system_update now updates repositories before performing upgrade (apt/emerge)
-  dust now checks for unknown options
-  several small bug fixes and improvements


0.5.0
------------

-  improved mysql recipe. it now accepts every option (change your configuration accordingly)

    recipes:
      mysql:
        mysqld:
          bind-address: 0.0.0.0
          port: 1234
        mysqldump:
          quick: false
        isamchk:
          key_buffer: 128M

-  fixes a bug in the ssh_authorized_keys recipe with ~user shortcut, uses new get_home method now
-  fixes a bug in the duplicity recipe occuring when using yaml files with multiple hostnames
-  fixes a bug where @node.get_home was returning nil


0.4.5
------------

-  node.write and node.append now not using echo for writing files on the server anymore.
   this solves problems with binary files and files including backticks (`)
-  adds pacemaker recipe, for basic setup and configuration of corosync/pacemaker
-  adds sudoers recipe for maintaining your sudoers rules
-  postgres recipe now checks if zabbix is installed, and if so configures the node for monitoring


0.4.4
------------

sshd recipe

-  default PrintMotd to false on apt systems (will be displayed 2 times otherwise)
-  no and yes can be specified in config file, without getting converted to booleans automatically 


0.4.3
------------

adds sshd recipe, which configures sshd_config. all sshd options are supported, with more or less intelligent default settings.
usage:

    recipes:
      sshd:
        Port: 12345
        X11Forward: yes


0.4.2
------------

adds hash_check recipe, which can check for weak hashes (according to provided list) in your /etc/shadow files.
can be used e.g. for making sure that none of your servers still has the template password.


0.4.1
------------

switches to the new recipe superclass. please upgrade your recipes and templates
-  quick hint: change node -> @node and config/ingredients -> @config, options -> @options
-  the new system makes it easier to write recipes, and you can also use methods more easily, as configuration and node are class-wide private variables now.
-  if you need more information, best have a look at the iptables recipe at https://github.com/kechagia/dust-deploy/blob/master/lib/dust/recipes/iptables.rb (or one of the others)


0.3.3
------------

-  fixes iptables bug, DENY policy target only allowed for filter table
-  if hostname is an ip, domain will be ignored while connecting.
   this fixes a conncetion issue, when hostname is an ip address and domain is specified nonetheless


0.3.2
------------

-  huge refactoring was done to the iptables recipe, no config changes needed on your side though.
-  iptables now supports table support for rpm machines
-  reduced verbosity for iptables recipe


0.3.1
------------

-  hacked in nat table support for rpm-like systems, no support for other tables yet though (like mangle)
-  small adjustment in repositories recipe


0.3.0
------------

refactoring was done, you may have to upgrade your recipes.
-  options for all node.* functions having an options={:quiet => false, :indent => 1} paremeter now, instead of plain arguments
-  adds 2 new dust options
   -  dust exec 'command'  # executes a command on all servers
   -  dust system_update   # runs a full system upgrade on all servers
-  small adjustments and improvements

if you encounter bugs, please report.


0.2.3
------------

-  improved iptables rule sorting, several minor improvements


0.2.2
------------

-  iptables will now sort rules before applying. thus enabling you to set the order of the rules.

    recipes:
      iptables:
        forward:
          1invalid: { match: state, state: INVALID, jump: DROP }
          2valid: { jump: ACCEPT }

-  removed all predefined iptables rules, you have (and can) do anything by yourself now
-  small fixes and improvements for iptables recipes
-  if you dont specify a chain, it will be set to ACCEPT per default
-  dust list is now the default when launching dust without an argument


0.2.1
------------

fixes small iptables issue when using --jump REDIRECT and --to-port


0.2.0
------------

heavily refactors iptables recipe. you HAVE to adapt your iptables settings. new usage:

    recipe:
      iptables:
        input:
          ssh: { dport: 22, match: state, state: NEW }
          http: { dport: [ 80, 443 ], match: state, state: NEW }
          spoof-protection: 
            in-interface: eth0
            source: [ 127.0.0.0/8, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 ]
            jump: DROP
        output:
          drop-everything: { jump: DROP }

every iptables long option is allowed, it tries to automatically detect whether to use iptables, ip6tables or both.
known issues: --to-destination is not checked for ipv4/ipv6, because it might include port numbers.
default jump target ist ACCEPT

basic rules are added automatically, see iptables.rb for more information.

**known issue:** the order of your rules is not enforced, due to hashes by definition not having an order, and using arrays would mess up inheritance. thus, be careful and doublecheck if rules are correctly interpreted when making statements that require a specific ordering of the rules, like the following:

    forward:
      invalid: { match: state, state: INVALID, jump: DROP }
      valid: { jump: ACCEPT }


0.1.8
------------

adds recipe for making sure packages are _uninstalled_
usage:

    recipes:
      remove_packages: [ package1, package2, ... ]


0.1.7
------------

repository repcipe now updates repos after deploying
