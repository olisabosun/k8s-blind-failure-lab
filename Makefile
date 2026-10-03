.PHONY: up down status snapshot inject reveal log kubeconfig verify

up:            ## build the 3-node cluster
	vagrant up cp && vagrant up w1 w2

down:          ## destroy everything
	vagrant destroy -f

status:        ## nodes + non-running pods
	KUBECONFIG=.cluster/admin.conf kubectl get nodes -o wide && \
	KUBECONFIG=.cluster/admin.conf kubectl get pods -A | grep -v Running || true

verify:        ## end-to-end smoke test: schedule, network, DNS
	bash scripts/verify.sh

snapshot:      ## take an etcd snapshot now
	vagrant ssh cp -c 'sudo /usr/local/sbin/etcd-snapshot'

inject:        ## inject a random failure (ONLY=name to choose)
	bash chaos/inject.sh $(if $(ONLY),--only $(ONLY),)

reveal:        ## unseal the active failure
	bash chaos/reveal.sh

log:           ## new log entry
	bash scripts/new-log-entry.sh

kubeconfig:    ## print export line for host kubectl
	@echo "export KUBECONFIG=$(PWD)/.cluster/admin.conf"

help:
	@grep -E '^[a-z]+: +##' Makefile | sed 's/:.*## /\t/'
