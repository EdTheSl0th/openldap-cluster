resource "hcloud_server" "vm" {
  for_each    = local.vms
  name        = each.key
  image       = each.value.image
  server_type = each.value.server_type
  location    = var.location
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  network {
    network_id = hcloud_network.internal_network.id
    ip         = each.value.private_ip
  }
  firewall_ids = local.firewall_ids
  ssh_keys     = local.ssh_public_keys
  user_data = templatefile("${path.module}/cloud-init/cloud-init.yaml", {
    hostname            = each.key
    fqdn                = each.value.fqdn
    ssh_user            = var.ssh_user
    ssh_authorized_keys = [tls_private_key.provisioning_key.public_key_openssh]
  })
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.provisioning_key.private_key_openssh
    host        = self.ipv4_address
    timeout     = "5m"
  }
  # Only return once the VM is fully booted, so Ansible can run right away.
  provisioner "remote-exec" {
    inline = [
      "sudo timeout 900 cloud-init status --wait --long",
    ]
  }

  depends_on = [hcloud_network_subnet.server-subnet]
}
