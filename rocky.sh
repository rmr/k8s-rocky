#!/bin/bash
# examples: https://igoipy.com/posts/2018/02/cloning-kvm-virtual-host_machines/
# https://wiki.libvirt.org/page/Tips

set -x

base=$(dirname $(realpath "${BASH_SOURCE[0]}"))
export LIBVIRT_DEFAULT_URI=qemu:///system
disk_size="20"
out_dir=${1:-$base}
libvirt_net="192.168.123.1"
machine_name="master"
network_name="rocky-k8s"

init() {
  if [ ! -e $out_dir/rocky.iso ] ; then
    curl -L https://download.rockylinux.org/pub/rocky/8.5/isos/x86_64/Rocky-8.5-x86_64-minimal.iso -o $out_dir/rocky.iso
  fi

  if [ "$(md5sum $out_dir/rocky.iso)" != "427b9397df7df0d1781caaed6f4ba009" ] ; then
    curl -L https://download.rockylinux.org/pub/rocky/8.5/isos/x86_64/Rocky-8.5-x86_64-minimal.iso -o $out_dir/rocky.iso
  fi
}

cleanup() {
    state="$(virsh list | grep " $machine_name " | awk '{ print $3 }')"
    if [ "${state}" = "running" ]; then
        virsh destroy $machine_name
    fi
    if $(virsh list --all | grep -q $machine_name); then
        virsh undefine $machine_name
    fi

    [ -f $out_dir/$machine_name.img ] && rm -f $out_dir/$machine_name.img
    [ -f $out_dir/$machine_name.raw ] && rm -f $out_dir/$machine_name.raw

    if ! $(which virt-host-validate > /dev/null 2>&1) ; then
        echo "Please install libvirt"
        exit 1
    fi

    if $(virt-host-validate | grep -q FAIL) ; then
        virt-host-validate
        exit 1
    fi

    if ! $(qemu-system-x86_64 -M help | grep -q q35); then
        echo "Qemu error"
        exit 1
    fi

    if ! $(grep -q "intel_iommu=on pci-stub.ids=8086:0b2b vfio-pci.ids=1c2c:1000,8086:6f0a" /proc/cmdline); then
        echo "Update /proc/cmdline to have, using /boot/grub/grub.cfg"
        echo "intel_iommu=on pci-stub.ids=8086:0b2b vfio-pci.ids=1c2c:1000,8086:6f0a"
        exit 0
    fi

    if ! $(grep -r -q "options vfio-pci ids=1c2c:1000,0424:2660,8086:1591,1546:01a9,1374:0001,0424:2514" /etc/modprobe.d); then
        echo "Modprobe needs to be updated, reboot after creating /etc/modprobe.d/vfio.conf with the following information"
        echo "echo 'options vfio-pci ids=1c2c:1000,0424:2660,8086:1591,1546:01a9,1374:0001,0424:2514' > /etc/modprobe.d/vfio.conf"
        exit 0
    fi

    qemu-img create -f raw $out_dir/$machine_name.raw ${disk_size}G

    if $(virsh net-list | grep -q $network_name); then
        virsh net-destroy $network_name
        virsh net-undefine $network_name
    fi

    virsh net-define --file $out_dir/$network_name.xml
    virsh net-start $network_name

    # virsh pool-destroy default
    # virsh pool-create pool-g9.xml

    while ! $(nslookup $machine_name.rocky.k8s.local $libvirt_net > /dev/null 2>&1) ; do
        echo "Waiting for dns"
        sleep 2
    done

    node_ip=$(nslookup $machine_name.rocky.k8s.local $libvirt_net | sed -n 's/Address: \(.*\)/\1/p')
}

create_nodes() {
    virt-install --name $machine_name $hvm \
                 --connect="qemu:///system" \
                 --virt-type kvm \
                 --hvm \
                 --accelerate \
                 --machine q35 \
                 --memory 16000 \
                 --disk path=$out_dir/$machine_name.img,format=raw,readonly=no,size=$disk_size \
                 --network network=$network_name,mac="$(virsh net-dumpxml $network_name | grep $machine_name | grep mac | sed "s/ name=.*//g" | sed -n "s/.*mac='\(.*\)'/\1/p")" \
                --vcpus=8 \
                --os-type linux \
                --location $out_dir/rocky.iso \
                --disk size=$disk_size  \
                --check disk_size=off \
                --import \
                --graphics=none \
                --os-variant=rhl8.0 \
                --noautoconsole \
                --console pty,target_type=serial \
                --initrd-inject $(pwd)/ks.cfg \
                --extra-args "inst.ks=file:/ks.cfg console=tty0 console=ttyS0,115200n8"

    sleep 10
    virsh console $machine_name
    sleep 30
    if $(virsh domblklist $machine_name | grep -q rocky.iso) ; then
        echo "Removing installation ISO"
        virsh change-media $machine_name --eject $(virsh domblklist $machine_name | grep rocky.iso | awk '{print $1}')
    fi
    virsh start $machine_name
    sleep 10
}

cleanup
init
create_nodes

while ! $(ping -c 1 -W 2 $node_ip >> /dev/null 2>&1) ; do
    echo "Waiting for Ping"
    sleep 5
done

while ! $(nc -z $node_ip 22 >> /dev/null 2>&1) ; do
    echo "Waiting for SSH"
    sleep 5
done

cat << EOF > $out_dir/ssh-config
host $node_ip
	User $machine_name
	StrictHostKeyChecking no
	UserKnownHostsFile /dev/null
EOF

sshpass -p123456 scp -F $out_dir/ssh-config provision.sh root@$node_ip:/root/provision.sh
sshpass -p123456 ssh -F $out_dir/ssh-config root@$node_ip bash /root/provision.sh
sshpass -p123456 scp -F $out_dir/ssh-config root@$node_ip:/root/.kube/config $out_dir/k8s-config
chmod 0600 $out_dir/k8s-config
echo "KUBECONFIG=$out_dir/k8s-config" > $out_dir/k8s-env

sshpass -p123456 scp -F $out_dir/ssh-config sts/setup-ice.sh root@$node_ip:/root/setup-ice.sh
sshpass -p123456 ssh -F $out_dir/ssh-config root@$node_ip bash -c "/root/setup-ice.sh unstable"

sshpass -p123456 scp -F $out_dir/ssh-config dfl/setup-dfl.sh root@$node_ip:/root/setup-dfl.sh
sshpass -p123456 ssh -F $out_dir/ssh-config root@$node_ip bash -c "/root/setup-dfl.sh"

virsh attach-device --file dfl/pci-passthrough-g9.xml --config master
virsh attach-device --file sts/pci-passthrough-g9.xml --config master

virsh reboot $machine_name
sleep 10

while ! $(ping -c 1 -W 2 $libvirt_net >> /dev/null 2>&1) ; do
    echo "Waiting for Ping"
    sleep 5
done

while ! $(nc -z $libvirt_net 22 >> /dev/null 2>&1) ; do
    echo "Waiting for SSH"
    sleep 5
done

curl -sL https://get.helm.sh/helm-v3.8.0-linux-amd64.tar.gz -o helm.tar.gz
tar xvf helm.tar.gz
chmod +x linux-amd64/helm
