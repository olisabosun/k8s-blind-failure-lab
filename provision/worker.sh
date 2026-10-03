#!/usr/bin/env bash
# Runs on workers. Waits for the join script written by cp, then joins.
set -euxo pipefail
: "${NODE_NAME:?}"

for _ in $(seq 1 60); do
  [[ -s /vagrant/.cluster/join.sh ]] && break
  sleep 10
done
[[ -s /vagrant/.cluster/join.sh ]] || { echo "join.sh never appeared - bring up cp first"; exit 1; }

bash /vagrant/.cluster/join.sh --node-name "${NODE_NAME}"

# kubectl on workers is for the chaos scripts and for you when cp is sick.
mkdir -p /root/.kube /home/vagrant/.kube
cp /vagrant/.cluster/admin.conf /root/.kube/config
cp /vagrant/.cluster/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
