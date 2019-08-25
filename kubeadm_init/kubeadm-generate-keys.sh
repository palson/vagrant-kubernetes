#!/usr/bin/env bash

set -o pipefail

while getopts ":i:n:v:" opt; do
  case ${opt} in
    i) MASTER_IP="$OPTARG" ;;
    n) CLUSTER_NAME="$OPTARG" ;;
    v) K8S_VERSION="$OPTARG" ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done


set +a
export SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
export OUTPUT_DIR="${SCRIPT_DIR}/_clusters/${CLUSTER_NAME}"
export LOCAL_CERTS_DIR=${OUTPUT_DIR}/pki
export KUBECONFIG=${OUTPUT_DIR}/kubeconfig
export MASTER_IP
export CLUSTER_NAME
export K8S_VERSION
set -a

function echoHeader {
  printf -- "--------------------------------------------\n\n"
  printf  "\n\n[INFO] $1\n\n"
}

check_kubeadm() {
  if [[ ! $(which kubeadm) ]]; then
    printf "\n\n[ERROR] kubeadm isn't installed.\nhttps://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/\n\n"
    # exit 1
    sudo bash -c "$(declare -f install_kubeadm); install_kubeadm"
  fi
}

install_kubeadm() {
  apt-get update && sudo apt-get install -y apt-transport-https curl
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >> /etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubeadm  
}

generate_kubeadm_init_config() {
  echoHeader "Generate kubeadm init config"
  envsubst < templates/init_config.tmpl.yml > ${OUTPUT_DIR}/kubeadm_init_config.yml
}

generate_kubeadm_join_config() {
  echoHeader "Generate kubeadm join config"
  envsubst < templates/join_config.tmpl.yml > ${OUTPUT_DIR}/kubeadm_join_config.yml
}

generate_certs() {
  echoHeader "Generate certificates"
  echo "Output dir: ${OUTPUT_DIR}"
  kubeadm init phase certs all --config ${OUTPUT_DIR}/kubeadm_init_config.yml
}

generate_client_certs() {
  echoHeader "Generate client certs "

  CERTS_DIR=${LOCAL_CERTS_DIR}
  CA="${CERTS_DIR}"/ca.crt
  CA_KEY="${CERTS_DIR}"/ca.key

  if [[ ! -f ${CA} || ! -f ${CA_KEY} ]]; then
    echo "Error: CA files ${CA}  ${CA_KEY} are missing "
    exit 1
  fi

  CLIENT_SUBJECT=${CLIENT_SUBJECT:-"/O=system:masters/CN=kubernetes-admin"}
  CLIENT_CSR=${CERTS_DIR}/kubeadmin.csr
  CLIENT_CERT=${CERTS_DIR}/kubeadmin.crt
  CLIENT_KEY=${CERTS_DIR}/kubeadmin.key
  CLIENT_CERT_EXTENSION=${CERTS_DIR}/cert-extension

# We need faketime for cases when your client time is on UTC+
  which faketime >/dev/null 2>&1
  if [[ $? == 0 ]]; then
    OPENSSL="faketime -f -1d openssl"
  else
    echo "Warning, faketime is missing, you might have a problem if your server time is less tehn"
    OPENSSL=openssl
  fi

  echo "OPENSSL = $OPENSSL "
  echo "Creating Client KEY $CLIENT_KEY "
  $OPENSSL genrsa -out "$CLIENT_KEY" 2048

  echo "Creating Client CSR $CLIENT_CSR "
  $OPENSSL req -subj "${CLIENT_SUBJECT}" -sha256 -new -key "${CLIENT_KEY}" -out "${CLIENT_CSR}"

  echo "--- create  ca extfile"
  echo "extendedKeyUsage=clientAuth" > "$CLIENT_CERT_EXTENSION"

  echo "--- sign  certificate ${CLIENT_CERT} "
  $OPENSSL x509 -req -days 1096 -sha256 -in "$CLIENT_CSR" -CA "$CA" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$CLIENT_CERT" -extfile "$CLIENT_CERT_EXTENSION" -passin pass:"$CA_PASS"
}

generate_kubeconfig() {
  echoHeader "Generate kubeconfig"
  set -a
  CLIENT_CERT_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.crt)
  CLIENT_KEY_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.key)
  CA_DATA_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/ca.crt)
  set +a
  envsubst < templates/kube_config.tmpl.yml > ${OUTPUT_DIR}/kubeconfig
}


main(){

  check_kubeadm 

  cd ${SCRIPT_DIR}
  mkdir -p ${OUTPUT_DIR}

  export KUBEADM_TOKEN=$(kubeadm token generate)

  generate_kubeadm_init_config

  generate_certs
  
  echoHeader "Generating CA certs Hash"
  export CA_CERT_HASH=$(openssl x509 -pubkey -in ${LOCAL_CERTS_DIR}/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* /sha256:/')

  generate_client_certs

  generate_kubeconfig

  generate_kubeadm_join_config
} 

main $@



