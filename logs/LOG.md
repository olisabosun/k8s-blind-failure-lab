# Failure log

One row per injected failure. Detail lives in `entries/`. This table is the artifact:
a dated, timed record of debugging a real control plane blind.

| # | Date | Failure | Node | Symptom (first observation) | Root cause | Fix (one line) | Time to RC | Time to fix | Solo? |
|---|------|---------|------|-----------------------------|------------|----------------|-----------:|------------:|:-----:|
| 000 | 2026-10-03 | *example* | w1 | `kubectl get nodes` → w1 NotReady, "cni plugin not initialized" | `/etc/cni/net.d` emptied; flannel only writes it at pod init | delete kube-flannel pod on w1 → init container rewrote config | 7m | 2m | yes |

**Solo?** = recovered without the undo script.

## Running stats

| Failure | Attempts | Median time to RC | Best | Notes |
|---------|---------:|------------------:|-----:|-------|
| expired-certs | 0 | | | |
| corrupt-etcd | 0 | | | |
| delete-cni | 0 | | | |
| full-disk | 0 | | | |
| bad-kubelet-config | 0 | | | |
| break-dns | 0 | | | |
| exhaust-node | 0 | | | |
