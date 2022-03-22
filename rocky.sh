#!/bin/bash
# examples: https://igoipy.com/posts/2018/02/cloning-kvm-virtual-host_machines/
# https://wiki.libvirt.org/page/Tips

set -x

base=$(dirname $(realpath "${BASH_SOURCE[0]}"))
export LIBVIRT_DEFAULT_URI=qemu:///system
disk_size="20"
out_dir=${1:-$base}
libvirt_net="192.168.123.1"

init() {
  if [ ! -e $out_dir/rocky.iso ] ; then
    curl -L https://download.rockylinux.org/pub/rocky/8.5/isos/x86_64/Rocky-8.5-x86_64-minimal.iso -o $out_dir/rocky.iso
  fi
}

cleanup() {
    state="$(virsh list --all | grep master | awk '{ print $3 }')"
    if [ "${state}" = "running" ]; then
        virsh destroy master
    fi
    if $(virsh list --all | grep -q master); then
        virsh undefine master
    fi

    [ -f $out_dir/master.img ] && rm -f $out_dir/master.img
    [ -f $out_dir/master.raw ] && rm -f $out_dir/master.raw

    if ! $(which virt-host-validate > /dev/null 2>&1) ; then
        echo "Please install libvirt"
        exit 1
    fi

    if ! $(virt-host-validate) ; then
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

    qemu-img create -f raw $out_dir/master.raw ${disk_size}G

    if $(virsh net-list | grep -q rocky-k8s); then
        virsh net-destroy rocky-k8s
        virsh net-undefine rocky-k8s
    fi

    virsh net-define --file $out_dir/rocky-k8s.xml
    virsh net-start rocky-k8s

    # virsh pool-destroy default
    # virsh pool-create pool-g9.xml

    while ! $(nslookup master.rocky.k8s.local $libvirt_net > /dev/null 2>&1) ; do
        echo "Waiting for dns"
        sleep 2
    done

    node_ip=$(nslookup master.rocky.k8s.local $libvirt_net | sed -n 's/Address: \(.*\)/\1/p')
}

create_nodes() {
    hvm=""

    device="$(lspci -d 1c2c:1000 | awk '{ print $1 }')"
    lspci_args=""
    if [ $hostname = "worker1" ] ; then
        if [ ! -z "$device" ] ; then
        lspci_args="--hostdev $device"
        fi
    fi

    if [ ! -z "$(lsusb -d 0424:2660)" ] ; then
      lspci_args=" --hostdev 0424:2660 "
      lspci_args=" $lspci_args --hostdev 1546:01a9 "
      lspci_args=" $lspci_args --hostdev 1374:0001 "
      for arg in $(lspci -d 8086:1591 | awk '{ print $1 }') ; do
        lspci_args=" $lspci_args --hostdev $arg,address.domain=0,address.bus=0x2,address.slot=0x0,address.function=$(echo $arg | cut -d . -f 2),address.type='pci'"
      done
      hvm="--hvm $lspci_args"
    elif [ ! -z "$(lsusb -d 0424:2514)" ] ; then
      lspci_args=" --hostdev 0424:2514 "
      lspci_args=" $lspci_args --hostdev 1546:01a9 "
      lspci_args=" $lspci_args --hostdev 1374:0001 "
      for arg in $(lspci -d 8086:1591 | awk '{ print $1 }') ; do
        lspci_args=" $lspci_args --hostdev $arg,address.domain=0,address.bus=0x2,address.slot=0x0,address.function=$(echo $arg | cut -d . -f 2),address.type='pci'"
      done
      hvm="--hvm $lspci_args"
    fi

    #
    # https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/5/html/virtualization/sect-virtualization-adding_a_pci_device_to_a_host_with_virt_install
    # virsh nodedev-list --tree
    # virsh nodedev-list | grep pci
    #
    virt-install --name master $hvm \
                 --connect="qemu:///system" \
                 --virt-type kvm \
                 --accelerate \
                 --machine q35 \
                 --memory 16000 \
                 --disk path=$out_dir/master.img,format=raw,readonly=no,size=$disk_size \
                 --network network=rocky-k8s,mac="$(virsh net-dumpxml rocky-k8s | grep master | grep mac | sed "s/ name=.*//g" | sed -n "s/.*mac='\(.*\)'/\1/p")" \
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
                #--extra-args="ks=http://192.168.122.1/ks.cfg console=tty0 console=ttyS0,115200n8"

    sleep 10
    virsh console master
    sleep 30
    if $(virsh domblklist master | grep -q rocky.iso) ; then
        echo "Removing installation ISO"
        virsh change-media master --eject $(virsh domblklist master | grep rocky.iso | awk '{print $1}')
    fi
    virsh start master
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
	User rocky
	StrictHostKeyChecking no
	UserKnownHostsFile /dev/null
EOF

sshpass -p123456 scp -F $out_dir/ssh-config setup-ice.sh root@$node_ip:/root/setup-ice.sh
sshpass -p123456 ssh -F $out_dir/ssh-config root@$node_ip bash -c "/root/setup-ice.sh unstable"

virsh reboot master
sleep 10

while ! $(ping -c 1 -W 2 $libvirt_net >> /dev/null 2>&1) ; do
    echo "Waiting for Ping"
    sleep 5
done

while ! $(nc -z $libvirt_net 22 >> /dev/null 2>&1) ; do
    echo "Waiting for SSH"
    sleep 5
done
sshpass -p123456 scp -F $out_dir/ssh-config provision.sh root@$node_ip:/root/provision.sh
sshpass -p123456 ssh -F $out_dir/ssh-config root@$node_ip bash /root/provision.sh
sshpass -p123456 scp -F $out_dir/ssh-config root@$node_ip:/root/.kube/config $out_dir/k8s-config
chmod 0600 $out_dir/k8s-config
echo "KUBECONFIG=$out_dir/k8s-config" > $out_dir/k8s-env
