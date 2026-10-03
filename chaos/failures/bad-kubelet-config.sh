#!/usr/bin/env bash
# FAILURE: wrong kubelet config (any node). One random variant:
#   cgroup   - cgroupDriver mismatch with containerd (pods fail to start)
#   yaml     - config.yaml no longer parses (kubelet won't start)
#   port     - kubelet serves on wrong port (node Ready, but logs/exec/top break)
#   dns      - clusterDNS points nowhere (pods get a dead resolver)
source "$(dirname "$0")/_lib.sh"
CFG=/var/lib/kubelet/config.yaml
variant="${VARIANT:-$(pick cgroup yaml port dns)}"
undo_init "bad-kubelet-config ($variant)"

cp -a "$CFG" "$HIDE/config.yaml"
case "$variant" in
  cgroup) sed -i 's/^cgroupDriver: systemd/cgroupDriver: cgroupfs/' "$CFG" ;;
  yaml)   echo '- this list item does not belong in a mapping' >> "$CFG" ;;
  port)   echo 'port: 10255' >> "$CFG" ;;
  dns)    sed -i 's/^- 10\.96\.0\.10$/- 10.96.0.99/' "$CFG" ;;
esac
systemctl restart kubelet || true

undo_add 'cp -a '"$HIDE"'/config.yaml /var/lib/kubelet/config.yaml'
undo_add 'systemctl restart kubelet'
