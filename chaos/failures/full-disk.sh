#!/usr/bin/env bash
# FAILURE: root filesystem full (worker).
# Symptom: DiskPressure, evictions, image pulls failing, kubelet logs noisy.
source "$(dirname "$0")/_lib.sh"
undo_init "full-disk"

BALLAST=/var/cache/apt/.archive-ballast
avail=$(df --output=avail -B1 / | tail -1)
fallocate -l $(( avail - 20*1024*1024 )) "$BALLAST"   # leave ~20 MiB

undo_add "rm -f $BALLAST"
undo_add 'systemctl restart kubelet'
