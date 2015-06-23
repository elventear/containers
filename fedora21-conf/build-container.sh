#!/bin/bash
#
# Populate a fedora configuration with packages and a configured user (vagrant)
#
set -e
umask 022

set -x
date

. "$build_env"

# Need swap, because scipy build fails otherwise. Allow X11Forwarding
if VBoxControl --version &>/dev/null; then
    cat >> /etc/NetworkManager/dispatcher.d/fix-slow-dns <<EOF
#!/bin/bash
# Fix slow DNS by updating resolve.conf
# http://fedoraforum.org/forum/showthread.php?t=238593
# https://github.com/mitchellh/vagrant/issues/1172#issuecomment-42263664
# https://github.com/chef/bento/blob/master/scripts/fedora/fix-slow-dns.sh
echo 'options single-request-reopen' >> /etc/resolv.conf
EOF
    chmod 550 /etc/NetworkManager/dispatcher.d/fix-slow-dns
    systemctl restart NetworkManager
EOF
    dd if=/dev/zero of=/swap bs=1M count=1024
    mkswap /swap
    chmod 600 /swap
    swapon /swap
    echo '/swap none swap sw 0 0' >> /etc/fstab
    perl -pi -e 's{^(X11Forwarding) no}{$1 yes}' /etc/ssh/sshd_config
    systemctl restart sshd.service
    # Containers are protected by their hosts
    (
        systemctl stop firewalld.service
        systemctl disable firewalld.service
    ) >& /dev/null || true
fi

# Remove the VirtualBox guest additions here so that the
# initial boot on the client machines goes faster, since
# these are surely the wrong version.
rpms=$(rpm -qa | grep VirtualBox || true)
if [[ $rpms ]]; then
    # Remove the virtual box RPMs
    yum remove -y -q $rpms || true
fi


# https://bugzilla.redhat.com/show_bug.cgi?format=multiple&id=1171928
# error: unpacking of archive failed on file /sys: cpio: chmod
# error: filesystem-3.2-28.fc21.x86_64: install failed
# DEBUG: Don't run update so comment this line:
yum --assumeyes --exclude='filesystem*' update
date

# DEBUG: Can subtitute "yum-install.list" with "yum-debug.list" below:
yum --assumeyes install $(cat $build_conf/yum-install.list)
date

# DEBUG: Uncomment this:
# exit
#
# Exitting here will get a container which you can then use this to debug further:
# docker run -i -t -v "$(pwd)":/vagrant -h docker radiasoft/fedora /bin/bash -l
#

. "$build_conf/user-root.sh"
date

rm -f /etc/localtime
# Not ideal, but where is the user really?
ln -s /usr/share/zoneinfo/UCT /etc/localtime

id -u vagrant &>/dev/null || useradd --create-home vagrant
chmod -R a+rX "$build_conf"

# DEBUG: Uncomment this:
# exit
#
# If you want to retry building vagrant, you start docker (above) and then repeat:
# userdel -r vagrant; useradd -m vagrant; su - vagrant -c 'bash -x /user-vagrant.sh'

su --login vagrant -c "build_env='$build_env' bash '$build_conf/user-vagrant.sh'"
date