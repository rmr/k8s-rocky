#!/bin/sh


cd /root
git clone https://github.com/OPAE/linux-dfl-backport.git
cd linux-dfl-backport
git  checkout n5010/fpga-ofs-dev-5.15-lts
make
make install
make insmod

cat <<EOF | tee /lib/systemd/system/dfl-drivers.service
[Unit]
Description=Loads out of tree Intel DFL drivers

[Service]
User=root
Type=oneshot
ExecStart=make -C /root/linux-dfl-backport insmod

[Install]
WantedBy=multi-user.target
EOF

systemctl enable dfl-drivers.service

systemctl daemon-reload

sync
