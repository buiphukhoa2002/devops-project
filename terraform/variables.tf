variable "do_token" {
  description = "DigitalOcean personal access token"
  type        = string
  sensitive   = true
}

variable "ssh_fingerprint" {
  description = "Fingerprint of the SSH key registered in DigitalOcean (Settings → Security → SSH Keys)"
  type        = string
}

variable "droplet_name" {
  description = "Name of the droplet"
  type        = string
  default     = "mern-app"
}

variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "sgp1"
}

variable "size" {
  description = "Droplet size slug"
  type        = string
  default     = "s-2vcpu-4gb"
}
