# Applies to the public interface only; the private network is not filtered.
resource "hcloud_firewall" "fw" {
  name = "${var.env_name}-fw"

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.admin_ips
    description = "SSH from admin-IPs"
  }

  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = var.admin_ips
    description = "Ping from admin-IPs"
  }

  dynamic "rule" {
    for_each = var.extra_ports
    content {
      direction   = "in"
      protocol    = rule.value.protocol
      port        = rule.value.port
      source_ips  = var.admin_ips
      description = "Extra port ${rule.value.port}/${rule.value.protocol}"
    }
  }
}
