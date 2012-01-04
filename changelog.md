Changelog
=============

0.2.0
------------

heavily refactors iptables recipe. you HAVE to adapt your iptables settings. new usage:

recipe:
  iptables:
    input:
    - input:
      ssh: { dport: 22, match: state, state: NEW }
    - output:
      drop: { jump: DROP }

every iptables long option is allowed, it tries to automatically detect whether to use iptables, ip6tables or both.
known issues: --to-destination is not checked for ipv4/ipv6, because it might include port numbers.
default jump target ist ACCEPT

basic rules are added automatically, see iptables.rb for more information.


0.1.8
------------

adds recipe for making sure packages are _uninstalled_
usage:

recipes:
  remove_packages: [ package1, package2, ... ]


0.1.7
------------

repository repcipe now updates repos after deploying
