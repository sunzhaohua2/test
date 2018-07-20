# Kickstart file to build RHEL-7 KVM image

text
lang en_US.UTF-8
keyboard us
timezone --utc America/New_York
# add console and reorder in %post
bootloader --timeout=1 --location=mbr --append="console=tty0 crashkernel=auto"
auth --enableshadow --passalgo=sha512
selinux --enforcing
firewall --enabled --service=ssh
network --bootproto=dhcp --onboot=on
services --enabled=network,sshd,rsyslog,ovirt-guest-agent --disabled kdump,rhsmcertd
rootpw --iscrypted nope

#
# Partition Information. Change this as necessary
# This information is used by appliance-tools but
# not by the livecd tools.
#
zerombr
clearpart --all --initlabel
# autopart --type=plain --nohome # --nohome doesn't work because of rhbz#1509350
# autopart --type=plain # autopart is problematic in that it creates /boot and swap partitions rhbz#1542510
reqpart
part / --fstype="xfs" --ondisk=vda --size=8000
reboot

# Do not use --url, RHEL 7 anaconda may have a bug that excludes --repos if this is enabled
# url --url=http://download.devel.redhat.com/nightly/latest-RHEL-7/compose/Server/$basearch/os/

# Repositories; gets wiped out by Brew
repo --name="rhel7" --baseurl=http://download.eng.bos.redhat.com/rcm-guest/puddles/RHAOS/AtomicOpenShift/3.10/latest/x86_64/os/
#repo --name="rhel7" --baseurl=http://download.devel.redhat.com/nightly/latest-RHEL-7/compose/Server/$basearch/os/
#repo --name="rhel7-opt" --baseurl=http://download.devel.redhat.com/nightly/latest-RHEL-7/compose/Server-optional/$basearch/os/
#repo --name="cloud" --baseurl=http://download.devel.redhat.com/brewroot/repos/images-rhel-7.0-build/latest/$basearch/

# Packages
%packages
@core
kernel
nfs-utils
yum-utils

# pull firmware packages out
-aic94xx-firmware
-alsa-firmware
-alsa-lib
-alsa-tools-firmware
-ivtv-firmware
-iwl1000-firmware
-iwl100-firmware
-iwl105-firmware
-iwl135-firmware
-iwl2000-firmware
-iwl2030-firmware
-iwl3160-firmware
-iwl3945-firmware
-iwl4965-firmware
-iwl5000-firmware
-iwl5150-firmware
-iwl6000-firmware
-iwl6000g2a-firmware
-iwl6000g2b-firmware
-iwl6050-firmware
-iwl7260-firmware
-libertas-sd8686-firmware
-libertas-sd8787-firmware
-libertas-usb8388-firmware

# cloud-init does magical things with EC2 metadata, including provisioning
# a user account with ssh keys.
cloud-init

# RHV guest-agent
ovirt-guest-agent-common

# RHN hosted / sat
rhn-setup
yum-rhn-plugin

# need this for growpart, because parted doesn't yet support resizepart
# https://bugzilla.redhat.com/show_bug.cgi?id=966993
#cloud-utils

heat-cfntools

cloud-utils-growpart
# We need this image to be portable; also, rescue mode isn't useful here.
dracut-config-generic
dracut-norescue

# Needed initially, but removed below.
firewalld

# cherry-pick a few things from @base
tar
tcpdump
rsync

# Some things from @core we can do without in a minimal install
-biosdevname
-plymouth
#-NetworkManager
-iprutils

# rh-amazon-rhui-client
%end

#
# Add custom post scripts after the base post.
#
%post --erroronfail

# workaround anaconda requirements
passwd -d root
passwd -l root

# Create grub.conf for EC2. This used to be done by appliance creator but
# anaconda doesn't do it. And, in case appliance-creator is used, we're
# overriding it here so that both cases get the exact same file.
# Note that the console line is different -- that's because EC2 provides
# different virtual hardware, and this is a convenient way to act differently
echo -n "Creating grub.conf for pvgrub"
rootuuid=$( awk '$2=="/" { print $1 };'  /etc/fstab )
mkdir /boot/grub
echo -e 'default=0\ntimeout=0\n\n' > /boot/grub/grub.conf
for kv in $( ls -1v /boot/vmlinuz* |grep -v rescue |sed s/.*vmlinuz-//  ); do
  echo "title Red Hat Enterprise Linux 7 ($kv)" >> /boot/grub/grub.conf
  echo -e "\troot (hd0)" >> /boot/grub/grub.conf
  echo -e "\tkernel /boot/vmlinuz-$kv ro root=$rootuuid console=hvc0 LANG=en_US.UTF-8" >> /boot/grub/grub.conf
  echo -e "\tinitrd /boot/initramfs-$kv.img" >> /boot/grub/grub.conf
  echo
done

#link grub.conf to menu.lst for ec2 to work
echo -n "Linking menu.lst to old-style grub.conf for pv-grub"
ln -sf grub.conf /boot/grub/menu.lst
ln -sf /boot/grub/grub.conf /etc/grub.conf

# setup systemd to boot to the right runlevel
echo -n "Setting default runlevel to multiuser text mode"
rm -f /etc/systemd/system/default.target
ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
echo .

# this is installed by default but we don't need it in virt
echo "Removing linux-firmware package."
yum -C -y remove linux-firmware

# Remove firewalld; it is required to be present for install/image building.
echo "Removing firewalld."
yum -C -y remove firewalld --setopt="clean_requirements_on_remove=1"

echo -n "Getty fixes"
# although we want console output going to the serial console, we don't
# actually have the opportunity to login there. FIX.
# we don't really need to auto-spawn _any_ gettys.
sed -i '/^#NAutoVTs=.*/ a\
NAutoVTs=0' /etc/systemd/logind.conf

echo -n "Network fixes"
# initscripts don't like this file to be missing.
cat > /etc/sysconfig/network << EOF
NETWORKING=yes
NOZEROCONF=yes
EOF

# For cloud images, 'eth0' _is_ the predictable device name, since
# we don't want to be tied to specific virtual (!) hardware
rm -f /etc/udev/rules.d/70*
ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules

# simple eth0 config, again not hard-coded to the build hardware
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
BOOTPROTOv6="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
USERCTL="yes"
PEERDNS="yes"
IPV6INIT="yes"
PERSISTENT_DHCLIENT="1"
EOF

# set virtual-guest as default profile for tuned
echo "virtual-guest" > /etc/tuned/active_profile

# generic localhost names
cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

EOF
echo .

cat <<EOL > /etc/sysconfig/kernel
# UPDATEDEFAULT specifies if new-kernel-pkg should make
# new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel
EOL

# make sure firstboot doesn't start
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# workaround https://bugzilla.redhat.com/show_bug.cgi?id=966888
if ! grep -q growpart /etc/cloud/cloud.cfg; then
  sed -i 's/ - resizefs/ - growpart\n - resizefs/' /etc/cloud/cloud.cfg
fi

# allow sudo powers to cloud-user
echo -e 'cloud-user\tALL=(ALL)\tNOPASSWD: ALL' >> /etc/sudoers

# Disable subscription-manager yum plugins
sed -i 's|^enabled=1|enabled=0|' /etc/yum/pluginconf.d/product-id.conf
sed -i 's|^enabled=1|enabled=0|' /etc/yum/pluginconf.d/subscription-manager.conf

echo "Cleaning old yum repodata."
yum clean all

# clean up installation logs"
rm -rf /var/log/yum.log
rm -rf /var/lib/yum/*
rm -rf /root/install.log
rm -rf /root/install.log.syslog
rm -rf /root/anaconda-ks.cfg
rm -rf /var/log/anaconda*

echo "Fixing SELinux contexts."
touch /var/log/cron
touch /var/log/boot.log
mkdir -p /var/cache/yum
/usr/sbin/fixfiles -R -a restore

# remove random-seed so it's not the same every time
rm -f /var/lib/systemd/random-seed

# reorder console entries
sed -i 's/console=tty0/console=tty0 console=ttyS0,115200n8/' /boot/grub2/grub.cfg

cat /dev/null > /etc/machine-id
# add additional flags for the running image
sed -i -e 's/115200n8/115200n8 no_timer_check net.ifnames=0/' /boot/grub2/grub.cfg

# make grub changes persistent
sed -i -e 's/^\(GRUB_CMDLINE_LINUX=.*\)"/\1 no_timer_check net.ifnames=0 console=ttyS0,115200n8"/' /etc/default/grub
%end
