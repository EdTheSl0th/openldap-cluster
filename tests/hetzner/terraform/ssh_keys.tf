resource "tls_private_key" "provisioning_key" {
  algorithm = "ED25519"
}

locals {
  provisioning_private_key_path = abspath("${path.module}/.ssh/id_ed25519")
  provisioning_public_key_path  = abspath("${path.module}/.ssh/id_ed25519.pub")
}

resource "local_file" "provisioning_private_key" {
  content              = tls_private_key.provisioning_key.private_key_openssh
  filename             = local.provisioning_private_key_path
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_file" "provisioning_public_key" {
  content              = tls_private_key.provisioning_key.public_key_openssh
  filename             = local.provisioning_public_key_path
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "hcloud_ssh_key" "provisioning_key" {
  name       = "${var.env_name}-key"
  public_key = tls_private_key.provisioning_key.public_key_openssh
}
