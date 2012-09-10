Changelog
=============

0.16.1
------------

-  node.scp now supports recursive copying
-  node.mktemp now supports :type => 'directory' option
-  cjdroute recipe removed


0.16.0
------------

-  fixes an issue where the user was set to the sudo user when using node.scp, now defaults to root:root
-  updates and fixes for cjdroute recipe
-  adds node.selinuxenabled? and node.chcon
-  users recipe now changes selinux content of home and ssh dirs
-  improves motd recipe, now supports update-motd as well. there are three possible ways of maintaining the motd now:
   using a motd string in the config file, and static file or a ERB template file. for more information see:
   https://github.com/kechagia/dust-deploy/wiki/motd

-  introduces node.get_gid()
-  users recipe now chowns to primary gid
-  users recipe now checks if public_keys.yaml and the requested user is actually present
-  removes the leading 10- from sysctl.d files, so they can be set individually if needed
-  sysctl recipe only applies rules directly if --restart is given
-  also enables support for multiple files, please migrate

    recipes:
      # old (deprecated)
      sysctl:
        key: value
     
      sysctl:
        # new
        name:
          key: value
        othername: { key: value }


0.15.2
------------

-  fixes a bug in node.manage_user, now returns correctly if user is already set up
-  node.manage_user now honors options correctly


0.15.1
------------

-  updates cjdroute public peers
-  readds dump option to chrony default config
-  chrony adds -r option on centos systems (apt systems use it by default)


0.15.0
------------

-  node.create_user -> node.migrate_user (supports now more options, make sure to migrate from :home -> 'home' if you use options
-  introduces users recipe
-  removes ssh_authorized_keys in favor of new users recipe (migrate your .yaml files!)

    recipes:
      users:
        myuser: { ssh_keys: kk, chmod: 0750, authorized_keys: [ user1, user2 ] }
        deploy: { shell: /bin/bash, home: /var/www, ssh_keys: deploy, skel: deploy }
        daemon: { system: true }
        unwanted_user: { remove: true }


0.14.1
------------

-  removes ntpd recipe
-  adds chrony recipe

    recipes:
      chrony: enabled


0.14.0
------------

-  migrates to new runner.rb
-  fixes bug in print_service_status
-  checks if sudo password is wrong (and raises an error)
-  fixes sudoers recipe when using with sudo (was deleting its own rules)


0.13.18
------------

-  adds support for ppa-repositories
-  fixes small bug with iptables ipv6 workaround
-  newrelic now works with non-apt systems
-  packages recipe now accepts https, http and ftp urls


0.13.17
------------

-  small bugfixes
-  postfix recipe now supports sql backends

    recipes:
      nginx:
        postfix:
          sql:
            relay_domains.cf:
              host: /var/run/postgresql
              user: postfixadmin
              dbname: postfix
              query: "SELECT domain FROM domain WHERE domain='%s' and backupmx = true"
            virtual_alias_maps.cf:
              host: /var/run/postgresql
              user: postfixadmin
              dbname: postfix
              query: "SELECT goto FROM alias WHERE address='%s' AND active = true"


0.13.16
------------

-  nginx also supports mulitple packages now

    recipes:
      nginx:
        package: [ nginx-extras, php-fpm ]


0.13.15
------------

-  postfix and dovecot recipes now support multiple packages.

    recipes:
      dovecot:
        package: [ dovecot-pgsql, dovecot-imapd ]


0.13.14
------------

-  fixes bug in iptables recipe (debian and ipv6)


0.13.13
------------

-  adds ssh_config recipe
-  fixes iptables workaround issues for debian and openwrt, uses workaround for ipv6 only on debian


0.13.12
------------

-  nginx recipe displays error message when configtest fails
-  nginx recipe supports specifying package to install
-  nginx recipe now uses binding for deploying nginx.conf (so you can call node.functions)

    recipes:
      nginx:
        package: nginx-extras
        sites:
          enabled: reverse-proxy


0.13.11
------------

-  fixes node.scp issue, when target was a directory instead of a full path (including filename)


0.13.10
------------

-  improves duplicity status


0.13.9
------------

-  introduces @node.package_min_version? to check if a package is at least version x.
   supports apt, rpm, pacman so far
-  improves iptables recipe (using iptables-restore now on all systems)


0.13.6
------------

-  fixes bug with dust status --parallel


0.13.5
------------

-  adds postfix recipe (for maintaining main.cf and master.cf)
-  adds dovecot recipe


0.13.4
------------

-  adds cron recipe that maintains cronjobs

    recipes:
      cron:
        mycronjob_name: { minute: '*/1', command: 'my command' }


0.13.3
------------

-  only display hostname in "waiting for servers" message, when there is actually something to deploy


0.13.2
------------

-  does not overwrite already present node variables (like hostname) when using facter anymore
-  adds "dust version"


0.13.1
------------

-  fixes small bug in summary
-  readds and updates cjdroute public peers
-  adds dnsmasq recipe


0.13.0
------------

-  introduces --parallel and --summary
   --summary -> warning e.g. shows a summary with all errors and warnings after completion

   --parallel -> deploy to all hosts in parallel, using threads

-  switches to new messaging system. using ::Dust.pring_* methods is now deprecated
   please migrate your recipes to the new @node.messages.add() system

    ::Dust.print_msg('checking something')
    ::Dust.print_ok

    msg = @node.messages.add('checking something')
    msg.ok


    ::Dust.print_ok('this went well')

    @node.messages.add('this went well').ok


    ::Dust.print_message('executing something')
    ::Dust.print_result(ret)

    msg = @node.messages.add('executing something')
    msg.parse_result(ret)
    

-  redis doesn't configure sysctl anymore, please use sysctl redis template

    recipes:
      sysctl:
        templates: redis


0.12.2
------------

-  makes cjdroute wait 2s before firing up again, should fix issues with cjdroute not coming up after upgrading


0.12.1
------------

-  introduces limits recipe, to maintain /etc/security/limits.d/*

    recipes:
      limits:
        nginx:
          - { domain: www-data, type: soft, item: nofile, value: 200000 }
          - { domain: www-data, type: hard, item: nofile, value: 700000 } 

-  nginx recipe now supports erb templates for nginx.conf as well
-  removes cjdroute public peers, since they are not supported anymore.
   you should find some friends on irc (efnet #cjdns)
-  modifies cjdroute recipe, to work with new ./do building setup


0.12.0
------------

-  introduces basic openwrt support!
-  fixes duplicity status bug


0.11.1
------------

-  updates list of public peers for cjdroute recipe


0.11.0
------------

-  refactors the postgres recipe, should now be cleaner and easier for standard setups.
   now supports profiles and defaults to postgresql-defaults.
   if you want to use the automatic configuration for dedicated servers (use all system ressources for the database), you have to specify "profile: dedicated" in your config file. have a look at the [postgres recipe wiki page](https://github.com/kechagia/dust-deploy/wiki/postgres) for information


0.10.8
------------

-  only use colors if stdout is a tty
-  switches to colorize gem
-  replaces basic_setup with skel recipe, to copy e.g. basic configuration files placed in templates/skel

    skel: [ root, john ]


0.10.7
------------

-  sshd recipe supports conditional blocks

    recipes:
      sshd:
        Match:
          User john:
            ChrootDirectory: /srv
            ForceCommand: internal-sftp
            AllowTcpForwarding: no
            X11Forwarding: no


0.10.6
------------

-  introduces ntpd recipe (basic ntpd installation)

    recipes:
      ntpd: enabled


0.10.5
------------

-  fixes a bug in postgres pacemaker.sh template (created when using 'dust new')
-  supports downloading of files (sudo not yet supported) using node.download


0.10.4
------------

-  cjdroute supports archlinux (and possibly gentoo) as well


0.10.3
------------

-  the hash_check recipe now supports python3
-  introduces basic archlinux support


0.10.2
------------

-  cjdroute now accepts the "commit" configuration option


0.10.1
------------

-  fixes an issue, where node.scp / node.write were not preserved if the file existed before
-  repositories recipe now accepts multiple releases for custom repos

   recipes:
     repositories:
       release: [ myrelease1, myrelease2 ]


0.10.0
------------

-  it is now possible to use ERB codes in your yaml configuration files.

    <% user = john %>

    hostname: <%= user %>-notebook

    recipes:
      ssh_authorized_keys:
        <%= user %>: admin

-  unattended upgrade recipe was removed in favor of the new apt recipe
-  postgres recipe: now adds a log_line_prefix as default
                    also accepts empty postgresql.conf in yaml configuration
-  apt recipe now looks for present proxy configurations and comments them out before applying new config
-  adds apt recipe to configure apt systems (unattended upgrades, proxy configuration, etc)
   you have to migrate your existing unattended_upgrade recipe from:

    recipes:
      unattended_upgrades: true

   to:
 
    recipes:
      apt:
        unattended_upgrades:
          enabled: 1

   or simply, in case you do not need other apt options (as enabling unattended_upgrades is the default):

    recipes:
      apt: enabled


0.9.2
------------

-  adds openssl dev packages as dependency for ruby_rvm recipe
-  improves @node.package_installed?, was failing for apt systems recently
-  sudo uses sh -c for executing commands, this prevents problems when > < || | && ; is used
-  repositories recipe now can handle keyring .deb files with the 'key' option


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
