# Purpose of this script.

Today, a lot of Internet providers use dynamic IP addresses for their clients (well, at least for IPv4).
This behavior is problematic if you plan to self-host some services because you need to always take care of the ip that resolve your domain.

A lot of solutions like DynDNS exist for managing this issue but few of them allow you to update a sub-domain of a domain that you own.
This script is an answer to this need.

# How to use it.

## Requirements.

  * The domain should be managed by the *Gandi* registrar.
  * Perl v5.10 min.
  * CPAN, or at least a way to download all Perl dependencies.

## How to install it.

  * Clone this Git repository in the `/opt/No-ip` folder.
  * Make symlinks of the *.target* and *.timer* files in the *systemd* folder to `/etc/systemd/system`.
  * Run `systemctl daemon-update` for making systemd aware of the new units.
  * Install the *systemd* timer for running this script periodically. In the theory, the stuff in the `systemd` folder will work for the creation of it, but at least for me, it's broken…
  * Run the script at least a first time by hand for ensuring that all dependencies are present on your computer.

## How to configure it.

An example of configuration is available in the `no-ip.sample.cfg` file.
Just copy it to `no-ip.cfg` and configure it correctly.