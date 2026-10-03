#!/usr/bin/env bash
# FAILURE: CNI config removed (worker).
# Symptom: node NotReady, "cni plugin not initialized", new pods stuck ContainerCreating.
source "$(dirname "$0")/_lib.sh"
undo_init "delete-cni"

cp -a /etc/cni/net.d "$HIDE/net.d"
rm -f /etc/cni/net.d/*
systemctl restart kubelet

undo_add 'cp -a '"$HIDE"'/net.d/. /etc/cni/net.d/'
undo_add 'systemctl restart kubelet'
