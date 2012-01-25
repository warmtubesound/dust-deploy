Changelog
=============

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
