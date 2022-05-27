#!/bin/bash

set -xe

export HOME=/root
export KUBECONFIG=/etc/kubernetes/admin.conf
export no_proxy=$no_proxy,.svc,.svc.cluster.local
export KUBECONFIG=$(pwd)/k8s-config
export VERSION=1.23:1.23.0
export OS=CentOS_8_Stream

curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/devel:kubic:libcontainers:stable.repo"
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo "https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo"

yum install -y cri-o kubelet kubeadm kubectl --disableexcludes=kubernetes
yum install -y podman libxml2 git make kernel-devel-$(uname -r)

swapoff -a
sed -n '/swap/d' /etc/fstab

systemctl daemon-reload
systemctl enable kubelet
systemctl enable crio
systemctl start crio

kubeadm config images pull

while ! $(ping -q -c 1 -W 5 8.8.8.8 > /dev/null 2>&1); do
    logger 'No network'
    sleep 1;
done

kubeadm init --pod-network-cidr=10.244.0.0/16 --v=5 2>&1 | tee  /root/kubeadm.log

mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown $(id -u):$(id -g) /root/.kube/config

# Single node cluster
kubectl taint nodes --all node-role.kubernetes.io/master-

kubectl version -o json
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
curl -sL https://github.com/derailed/k9s/releases/download/v0.25.18/k9s_Linux_x86_64.tar.gz -o /tmp/k9s.tar.gz
tar xvf /tmp/k9s.tar.gz
mv k9s /usr/local/bin/

while ! $(kubectl get pods -A | grep coredns | grep -q Running); do
    sleep 10;
    logger "Wating for coredns before adding nodes."
done

while ! $(kubectl get nodes | grep -q Ready); do
    sleep 10;
    logger "Waiting for kubctl"
done

systemctl daemon-reload

kubectl label nodes master sts.silicom.com/ptp="true"
kubectl label nodes master fpga.silicom.dk/dfl="true"

sync
