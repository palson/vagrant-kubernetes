## Overview
The project allows running multinode Kubernetes cluster by Vagrant.    
The default vagrant provider - VirtualBox.  
The Vagrantfile prepares k8s cluster via kubeadm with flannel network.

## Requirements
- **kubeadm**
- **vagrant** and **vagrant-env** plugin for it
- **VIrtualbox**

## Customization
- _.env_ file;
- `WORKERS_COUNT` in the _Vagrantfile_;

## Steps
The `run.sh` script combines all steps:
- generates certs and config for kubernetes
- set up a new cluster via vagrant
- applies prometheus manifests

### Generate certificates and kubeadm config
As the `kube-controller-manager` should be monitored, the default **bind-address** parameter for the controller-manager should be set to **0.0.0.0** instead of default localhost. The one way to do it for the kubeadm installation - via kubeadm config.  
The manual https://medium.com/@kosta709/kubernetes-by-kubeadm-config-yamls-94e2ee11244 is used as a base for it.   

To run the config generation as a separate step - cd to the _kubeadm\_init_ directory and run  
```
kubeadm-generate-keys.sh -i ${MASTER NODE IP ADDRESS} -n ${CLUSTER NAME} -v ${KUBERNETES VERSION}
```

### Vagrant
The `vagrant-env` should be installed to use the **.env** file.  
The variables that can be updated in the **.env** file are:  
- cluster nodes network
- the kubernetes version
- cluster name  

To update the cluster nodes count - see the **Vagrantfile**.  

The scripts in the **Vagrantfile** install docker, kubectl, kubeadm on all nodes.  
On the **master** node, the kubeadm init config and certificates from the previous step are used to install the kubernetes control plane.  
On the **worker** nodes, the  kubeadm join config is used to join a node to the master.  

To deploy new machines as a separate step - run:  
```
vagrant up
```

### Kubeconfig
To connect to a new cluster - run:
```
export KUBECONFIG=./kubeadm_init/_clusters/${CLUSTER_NAME}/kubeconfig 
```

### Prometheus
To install the prometheus deployment as a separate - run:
```
kubectl apply -f ./prometheus
```

This will create the prometheus deployment, service accounts, needed exporters and the endpoint for the **kube-controller-manager**.  

Prometheus will be accessible via http://${MASTER_IP}:30000


### The Prometheus alerts
There are four alerts that should be firing in the relevant cases:
- KubeControllerIsDown
- NodeCpuHigh
- NonPodCpuHigh
- PodMemoryHigh

#### KubeControllerIsDown
To check the alert - run:
```
vagrant ssh master -c "sudo mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/"
```

To return as it was - run after checking:
```
vagrant ssh master -c "sudo mv /tmp/kube-controller-manager.yaml  /etc/kubernetes/manifests/"
```

#### NodeCpuHigh and NonPodCpuHigh
```
vagrant ssh worker-1 -c "while true; do echo; done"
```

This will fire both alerts.  
To check the **NodeCpuHigh** only, run :
```
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: cpu-test-app
spec:
  containers:
  - name: cpu-test-app
    image: alpine
    command: ["/bin/sh"]
    args: ["-c", "while true; do echo; done"]
  nodeName: worker-1
EOF
```

### PodMemoryHigh
```
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: mem-test-app
spec:
  containers:
  - name: mem-test-app
    image: progrium/stress
    command: ["/bin/sh"]
    args: ["-c", "stress -m 1 --vm-bytes 1500M -t 300s"]
  nodeName: worker-1
EOF
```
