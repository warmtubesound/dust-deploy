Changelog
=============

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
