#!/bin/bash

set -xe

build_version=${1:-"stable"}

url=$(curl -sL 'https://sourceforge.net/projects/e1000/rss?path=/ice%20stable' | xmllint --xpath '//item/link[contains(text(),"tar.gz")]/text()' - | sed 's/download/download\n/g' | sort | tail -n1)
if [ $build_version != "stable" ] ; then
    url=$(curl -sL 'https://sourceforge.net/projects/e1000/rss?path=/unsupported/ice%20unsupported' | xmllint --xpath '//item/link[contains(text(),"tar.gz")]/text()' - | sed 's/download/download\n/g' | sort | tail -n1)
fi

version=$(echo $url | sed -n 's/.*ice-\(.*\).tar.gz.*/\1/p')

curl -L  $url -o /root/ice.tar.gz
tar xvf /root/ice.tar.gz -C /root
make -C /root/ice-$version/src -j4

mkdir -p /lib/firmware/intel/ice/ddp
rm -f /lib/firmware/intel/ice/ddp/ice.pkg
rm -f /lib/firmware/intel/ice/ddp/ice.ko
ln -s /root/ice-$version/ddp/ice-*.pkg  /lib/firmware/intel/ice/ddp/ice.pkg

[ ! -f /etc/modprobe.d/ice.conf ] && echo "blacklist ice" >> /etc/modprobe.d/ice.conf

cat <<EOF | tee /lib/systemd/system/ice-driver.service
[Unit]
Description=Loads out of tree Intel ICE Driver

[Service]
User=root
Type=oneshot
ExecStart=/usr/sbin/insmod /root/ice-$version/src/ice.ko

[Install]
WantedBy=multi-user.target
EOF

systemctl enable ice-driver.service

systemctl daemon-reload

# https://access.redhat.com/solutions/41278
dracut --omit-drivers ice -f -v

sync
