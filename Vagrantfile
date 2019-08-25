# -*- mode: ruby -*-
# vi: set ft=ruby :

WORKERS_COUNT    = 1

init = <<SCRIPT
#!/usr/bin/env bash
  set -e
  set -o pipefail

  source /vagrant/.env

  printf "\n\n[INFO] Updating cache\n\n"
  apt update -y
  apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common

  printf "\n\n[INFO] Installing Docker\n\n"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable"
  apt update -y
  apt install -y docker-ce docker-ce-cli containerd.io
  usermod -aG docker vagrant

  printf "\n\n[INFO] Removed swap (if it's enabled)\n\n"
  swapoff -a
  sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

  printf "\n\n[INFO] Installing kubeadm, kubelet, kubectl\n\n"
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  printf "deb http://apt.kubernetes.io/ kubernetes-xenial main" >> /etc/apt/sources.list.d/kubernetes.list
  apt-get update -y
  apt-get install -y kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00

  printf "\n\n[INFO] Configure node ip\n\n"
  IP_ADDR=`ifconfig enp0s8 | grep Mask | awk '{print $2}'| cut -f2 -d:`
  printf "KUBELET_EXTRA_ARGS=--node-ip=${IP_ADDR}" >> /etc/default/kubelet
  systemctl restart kubelet
SCRIPT

install_control_plane = <<SCRIPT
#!/usr/bin/env bash
  set -e
  set -o pipefail

  source /vagrant/.env


  printf "\n\n[INFO] Copy certifacates\n\n"
  mkdir -p /etc/kubernetes/pki
  cp -r /vagrant/kubeadm_init/_clusters/${CLUSTER_NAME}/pki/* /etc/kubernetes/pki/

  printf "\n\n[INFO] Copy kubeadm init config\n\n"
  cat /vagrant/kubeadm_init/_clusters/${CLUSTER_NAME}/kubeadm_init_config.yml | sed '/certificatesDir:/d' > /home/vagrant/kubeadm_init_config.yml

  printf "\n\n[INFO] Initialize the Kubernetes cluster\n\n"
  kubeadm init --skip-phases certs --config /home/vagrant/kubeadm_init_config.yml

  printf "\n\n[INFO] Setup kube config for the vagrant user\n\n"
  mkdir -p /home/vagrant/.kube
  cp -i /vagrant/kubeadm_init/_clusters/${CLUSTER_NAME}/kubeconfig /home/vagrant/.kube/config
  chown -R vagrant:vagrant /home/vagrant/.kube

  printf "\n\n[INFO] Install flannel pod network\n\n"
  kubectl --kubeconfig=/home/vagrant/.kube/config apply -f /vagrant/kube-flannel.yml

  kubectl --kubeconfig=/home/vagrant/.kube/config taint nodes --all node-role.kubernetes.io/master-

  printf "\n\n[INFO] Allow connection between VMs\n\n"
  sed -i "/^[^#]*PasswordAuthentication[[:space:]]no/c\PasswordAuthentication yes" /etc/ssh/sshd_config
  systemctl restart sshd

SCRIPT

install_worker = <<-SCRIPT
  source /vagrant/.env

  printf "\n\n[INFO] Join to the cluster\n\n"
  kubeadm join --config /vagrant/kubeadm_init/_clusters/${CLUSTER_NAME}/kubeadm_join_config.yml
SCRIPT

Vagrant.configure("2") do |config|
    config.vm.box = "ubuntu/xenial64"

    config.vm.provider "virtualbox" do |vb|
        vb.memory = 2048
        vb.cpus = 2
    end

    config.vm.provision :shell, inline: init
    config.env.enable

    config.vm.define "master" do |master|
        master.vm.network "private_network", ip: ENV['MASTER_IP']
        master.vm.hostname = "master"
        master.vm.provision :shell, inline: install_control_plane
    end

     (1..WORKERS_COUNT).each do |i|
      config.vm.define "worker-#{i}" do |worker|
          worker.vm.network "private_network", ip: "#{ENV['NODE_NTW']}#{20 + i}"
          worker.vm.hostname = "worker-#{i}"
          worker.vm.provision :shell, inline: install_worker
      end
    end
end
