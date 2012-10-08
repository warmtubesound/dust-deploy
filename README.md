# dust - a ssh only server deployment tool

dust is a deployment tool, kinda like sprinkle. but cooler (at least for me).
it's for those, who would like to maintain their servers with a tool like puppet or chef, but are scared by the thought of having configuration files, credentials and other stuff centrally on a server reachable via the internet.

although the tool is not as versatile and elite as puppet, it's still cool for most use cases, and easily extendable.


## installing

installation is quite simple. just 

    # gem install dust-deploy


## quickstart

let's start by creating a new directory skeleton

    $ dust new mynetwork
      - spawning new dust directory skeleton into 'mynetwork.dust' [ ok ]

this will create a directory called mynetwork.dust, the nodes, templates and recipes subdirectories and will copy over example templates and node configurations. hop into your new dust directory and see what's going on:

    $ cd mynetwork.dust

dust uses simple .yaml files for configuring your nodes.
let's start by adding a simple host:

    $ vi nodes/yourhost.yaml

and put in basic information:

    # the hostname (fqdn, or set the domain parameter as well, ip also works)
    # you don't need a password if you connect using ssh keys
    hostname: yourhost.example.com
    password: supersecretphrase

    # these are the default values, you have to put them in case you need something else.
    # be aware: sudo usage is not yet supported, but ssh keys are!
    port: 22
    user: root

    # because this alone won't tell dust what to do, let's for example install some useful packages
    recipes:
      packages: [ 'vim', 'git-core', 'rsync' ]


you can then save the file, and tell dust to get to work:

    $ dust deploy

    [ yourhost.example.com ]

    |packages|
     - checking if vim is installed [ ok ]
     - checking if git-core is installed [ failed ]
       - installing git-core [ ok ]
     - checking if rsync is installed [ ok ]

you should see dust connecting to the node, checking if the requested packages are installed, and if not, install them.

## supported distributions

dust works with **apt-get**, **yum**, **emerge**, **pacman** (since 0.10.3) and **opkg** (since 0.12.0) systems at the moment (testet with recent versions of **ubuntu**, **debian**, **gentoo**, **fedora**, **scientificlinux**, **centos** and **archlinux** as well as **openwrt**). should work on rhel without any problem, too.


## contribute

feel free to contribute to dust, so that your system is also supported. contribution is easy! just send me a github pull request. You can find the repository here: https://github.com/kechagia/dust-deploy


## documentation

for further documentation (this README only covers the very basics), head over to the github wiki:
https://github.com/kechagia/dust-deploy/wiki
