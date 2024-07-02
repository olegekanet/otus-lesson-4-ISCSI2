variable "yandex_zone" {
  description = "Зона, в которой будет создана виртуальные машины"
  default     = "ru-central1-a"
}

variable "image_id" {
  #  yc compute image list --folder-id standard-images | grep centos  # centos-7-v20240129
  description = "ID образа операционной системы для виртуальной машины"
  default     = "fd8933lf2cg088htd8sb"
}

variable "v4_cidr_blocks_default" {
  description = "блок v4 IP адресов для подсети на виртуалку"
  default     = ["10.5.0.0/24"]
}

variable "iscsi_static_ip" {
  description = "iscsi_static_ip"
  default     = "10.5.0.100"
}

variable "nodes_static_ips" {
  description = "nodes_static_ips"
  default     = ["10.5.0.11", "10.5.0.12", "10.5.0.13"]
}

variable "vpc_name" {
  description = "network name"
  default     = "terraform"
}

variable "node_count" {
  description = "node count"
  default     = 3
}
