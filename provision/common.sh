#!/usr/bin/env bash
# Runs on every node. Prepares the OS, installs containerd + kubeadm/kubelet/kubectl,
# plus the small toolset the chaos scripts and your diagnosis need.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${NODE_IP:?}" "${NODE_NAME:?}" "${K8S_VERSION:=1.31}"

# --- hostnames -------------------------------------------------------------
cat >> /etc/hosts <<HOSTS
192.168.56.10 cp
192.168.56.11 w1
192.168.56.12 w2
HOSTS

# --- kernel / swap ---------------------------------------------------------
swapoff -a
sed -i '/\sswap\s/s/^/#/' /etc/fstab
cat > /etc/modules-load.d/k8s.conf <<M
overlay
br_netfilter
M
modprobe overlay && modprobe br_netfilter
cat > /etc/sysctl.d/k8s.conf <<S
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
S
sysctl --system >/dev/null

# --- packages --------------------------------------------------------------
apt-get update -q
apt-get install -y -q apt-transport-https ca-certificates curl gpg jq \
  containerd stress-ng net-tools conntrack ethtool socat ipvsadm

# containerd with systemd cgroups (kubelet is configured to match; the
# bad-kubelet-config failure breaks exactly this agreement).
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.k8s.io/pause:3.10"#' /etc/containerd/config.toml
systemctl restart containerd && systemctl enable containerd

# --- kubeadm / kubelet / kubectl -------------------------------------------
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -q
apt-get install -y -q kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Vagrant's NAT interface (eth0) is first; make the kubelet advertise the private IP.
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
systemctl enable kubelet

# crictl talks to containerd directly - essential when the API server is down.
cat > /etc/crictl.yaml <<C
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
C

# etcdctl for snapshot/restore practice.
ETCD_VER=v3.5.16
curl -fsSL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz" \
  | tar -xz -C /usr/local/bin --strip-components=1 "etcd-${ETCD_VER}-linux-amd64/etcdctl" "etcd-${ETCD_VER}-linux-amd64/etcdutl"

# Pull images early so chaos is not confused with slow image pulls.
kubeadm config images pull --kubernetes-version "stable-${K8S_VERSION}" >/dev/null || true
