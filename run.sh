#!/usr/bin/env bash

set -e
set -o pipefail

function echoHeader {
  printf -- "--------------------------------------------\n\n"
  printf  "\n\n[INFO] $1\n\n"
}

SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
KUBEADM_INIT_DIR=${SCRIPT_DIR}/kubeadm_init

source  ${SCRIPT_DIR}/.env

echoHeader "Generate kube certs and configs"
cd "$KUBEADM_INIT_DIR"
./kubeadm-generate-keys.sh -i ${MASTER_IP} -n ${CLUSTER_NAME} -v ${K8S_VERSION}

cd "$SCRIPT_DIR"
if [[ ! $(vagrant plugin list | grep vagrant-env) ]]; then
  echoHeader "Installing vagrant-env plugin"
  vagrant plugin install vagrant-env
fi

cd $SCRIPT_DIR
vagrant up

echoHeader "Apply prometheus manifests"
export KUBECONFIG=${KUBEADM_INIT_DIR}/_clusters/${CLUSTER_NAME}/kubeconfig
echo $KUBECONFIG
kubectl apply -f ./prometheus

echoHeader "To expose the cluster from the admin host - run:\n
kubectl --kubeconfig=${KUBEADM_INIT_DIR}/_clusters/${CLUSTER_NAME}/kubeconfig get ..."


