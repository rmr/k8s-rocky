# K8S single node installation using rockylinux and libvirt
This is a repository which installs a simple installtion of k8s in a single node instance of a VM using libvirt. The VM is using PCI passthrough on the devices.
* Downloads and builds either the unsupported or stable version of the sourceforge ice driver
* Creates a one-shot systemd service file to insmod of the out-of-tree driver
* Installs a k8s, flannel, coredns

## Create node
`./rocky.sh`

## NOTES

### Network
The above will create a libvirt network using 192.168.123.1 with the domain *.rocky.k8s.local. The `rocky-k8s.xml` is the file used to define this network.

### KUBECONFIG
Following the successful installation of the node, the kubeconfig file will be copied out of the VM and into `k8s-config`.

`KUBECONFIG=$(pwd)/k8s-config kubectl cluster-info`

`virsh list`

### Passthrough DFL card
virsh attach-device --file dfl/pci-passthrough-g9.xml

### Passthrough STS card
virsh attach-device --file dfl/pci-passthrough-g9.xml

### Run OPAE
ssh root@192.168.123.2
podman run --rm -it --privileged -v /dev:/dev quay.io/silicom/opae-runtime:2.1.0-1 fpgainfo bmc

### Update fw with OPAE
scp fw.img root@192.168.123.2:/root
podman run --rm -it --privileged -v /dev:/dev -v /root:/root quay.io/silicom/opae-runtime:2.1.0-1 fpgasupdate /root/fw.img
