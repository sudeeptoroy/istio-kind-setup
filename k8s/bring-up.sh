#!/bin/bash

# https://piotrminkowski.com/2021/07/12/multicluster-traffic-mirroring-with-istio-and-kind/
# https://piotrminkowski.com/2021/07/08/kubernetes-multicluster-with-kind-and-submariner/
# https://github.com/piomin/sample-istio-services


set -e

# bring up kind cluster 1
kind create cluster --config=kind-c1.yaml

# bring up kind cluster 2
kind create cluster --config=kind-c2.yaml

# CNI
#curl https://projectcalico.docs.tigera.io/manifests/calico.yaml -O
#kubectl apply -f calico.yaml --context kind-c1
#kubectl apply -f calico.yaml --context kind-c2

#https://projectcalico.docs.tigera.io/getting-started/kubernetes/quickstart
kubectl create -f tigera-operator.yaml --context kind-c1
kubectl create -f tigera-operator.yaml --context kind-c2

kubectl create -f tigera-c1.yaml --context kind-c1
kubectl create -f tigera-c2.yaml --context kind-c2

# Sample deployment
kubectl create ns busybox-c1
kubectl -n busybox-c1 apply -f busybox.yaml

# install LB for the east west gw
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.11.0/manifests/namespace.yaml --context kind-c1
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.11.0/manifests/metallb.yaml --context kind-c1
o
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.11.0/manifests/namespace.yaml --context kind-c2
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.11.0/manifests/metallb.yaml --context kind-c2

#In order to complete the configuration, we need to provide a range of IP addresses MetalLB controls. We want this range to be on the docker kind network
docker network inspect -f '{{.IPAM.Config}}' kind

kubectl apply -f metallb-cm-c1.yaml --context kind-c1
kubectl apply -f metallb-cm-c2.yaml --context kind-c2

# istio
#export ISTIO_HOME=<path the istio>
# create certs and move it here

export CTX_CLUSTER1=kind-c1
export CTX_CLUSTER2=kind-c2

k --context kind-c1 create ns istio-system
k --context kind-c2 create ns istio-system

kubectl --context="${CTX_CLUSTER1}" get namespace istio-system && \
  kubectl --context="${CTX_CLUSTER1}" label namespace istio-system topology.istio.io/network=network1

kubectl --context="${CTX_CLUSTER2}" get namespace istio-system && \
  kubectl --context="${CTX_CLUSTER2}" label namespace istio-system topology.istio.io/network=network2

kubectl --context="${CTX_CLUSTER1}" create secret generic cacerts -n istio-system \
      --from-file=kind-c1/ca-cert.pem \
      --from-file=kind-c1/ca-key.pem \
      --from-file=kind-c1/root-cert.pem \
      --from-file=kind-c1/cert-chain.pem

kubectl --context="${CTX_CLUSTER2}" create secret generic cacerts -n istio-system \
      --from-file=kind-c2/ca-cert.pem \
      --from-file=kind-c2/ca-key.pem \
      --from-file=kind-c2/root-cert.pem \
      --from-file=kind-c2/cert-chain.pem


istioctl install -f istio-c1.yaml --context "${CTX_CLUSTER1}"
istioctl install -f istio-c2.yaml --context "${CTX_CLUSTER2}"

kubectl apply -f istio-ew-gw.yaml --context "${CTX_CLUSTER1}"
kubectl apply -f istio-ew-gw.yaml --context "${CTX_CLUSTER2}"

#istioctl x create-remote-secret \
#  --context="${CTX_CLUSTER1}" \
#  --name=kind-c1 | \
#  kubectl apply -f - --context="${CTX_CLUSTER2}"
#
#istioctl x create-remote-secret \
#  --context="${CTX_CLUSTER2}" \
#  --name=kind-c2 | \
#  kubectl apply -f - --context="${CTX_CLUSTER1}"

# Before applying generated secrets we need to change the address of the cluster. Instead of localhost and dynamically generated port, we have to use c1-control-plane:6443 for the first cluster, and respectively c2-control-plane:6443 for the second cluster

istioctl x create-remote-secret   --context="${CTX_CLUSTER1}"   --name=kind-c1 --server=https://c1-control-plane:6443 | kubectl apply -f - --context="${CTX_CLUSTER2}"

istioctl x create-remote-secret   --context="${CTX_CLUSTER2}"   --name=kind-c2 --server=https://c2-control-plane:6443 | kubectl apply -f - --context="${CTX_CLUSTER1}"


##
#APP

kubectl --context kind-c1 create ns busybox
kubectl --context kind-c1 create ns nginx
kubectl --context kind-c2 create ns nginx

kubectl --context kind-c1 label namespace busybox istio-injection=enabled
kubectl --context kind-c1 label namespace nginx istio-injection=enabled
kubectl --context kind-c2 label namespace nginx istio-injection=enabled
