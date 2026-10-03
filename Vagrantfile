# -*- mode: ruby -*-
# Three-node kubeadm cluster: 1 control plane + 2 workers.
# Nothing managed. The control plane is the point.

K8S_VERSION = ENV.fetch("K8S_VERSION", "1.31")
POD_CIDR    = "10.244.0.0/16"

NODES = {
  "cp" => { ip: "192.168.56.10", cpus: 2, mem: 2560, role: "control-plane" },
  "w1" => { ip: "192.168.56.11", cpus: 2, mem: 2048, role: "worker" },
  "w2" => { ip: "192.168.56.12", cpus: 2, mem: 2048, role: "worker" },
}

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.box_check_update = false
  config.vm.synced_folder ".", "/vagrant"

  NODES.each do |name, n|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network", ip: n[:ip]

      node.vm.provider "virtualbox" do |vb|
        vb.name   = "k8s-lab-#{name}"
        vb.cpus   = n[:cpus]
        vb.memory = n[:mem]
        # Let the guest keep its own clock: the expired-certs failure moves it.
        vb.customize ["guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", "999999999"]
      end

      node.vm.provider "libvirt" do |lv|
        lv.cpus   = n[:cpus]
        lv.memory = n[:mem]
      end

      env = { "NODE_IP" => n[:ip], "NODE_NAME" => name, "K8S_VERSION" => K8S_VERSION, "POD_CIDR" => POD_CIDR }
      node.vm.provision "shell", path: "provision/common.sh", env: env
      if n[:role] == "control-plane"
        node.vm.provision "shell", path: "provision/control-plane.sh", env: env
      else
        node.vm.provision "shell", path: "provision/worker.sh", env: env
      end
    end
  end
end
