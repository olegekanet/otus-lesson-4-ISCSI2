terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.41"
}

provider "yandex" {
  zone = var.yandex_zone
}

# Создание виртуальной частной сети (VPC)
resource "yandex_vpc_network" "lab_net" {
  name = var.vpc_name
  #folder_id   = var.yandex_folder_id
  description = "Lab network in Yandex.Cloud"
}

# Создание подсети внутри VPC
resource "yandex_vpc_subnet" "lab_subnet" {
  zone           = var.yandex_zone
  network_id     = yandex_vpc_network.lab_net.id
  v4_cidr_blocks = var.v4_cidr_blocks_default # Замените на нужный диапазон CIDR для вашей сети
}

# Генерация публичного и приватного ключей SSH
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Запись публичного ключа SSH в файл
resource "local_file" "ssh_key_pub" {
  filename = "${path.module}/id_rsa.pub"
  content  = tls_private_key.ssh_key.public_key_openssh
}

# Запись приватного ключа SSH в файл
resource "local_file" "ssh_key_private" {
  filename        = "${path.module}/id_rsa"
  content         = tls_private_key.ssh_key.private_key_pem
  file_permission = "0600"
}

resource "local_file" "cloud_config" {
  depends_on = [
    local_file.ssh_key_pub
  ]

  filename = "${path.module}/cloud-config.yaml"
  content  = <<-EOT
    #cloud-config
    users:
      - name: ubuntu
        groups: sudo
        shell: /bin/bash
        sudo: 'ALL=(ALL) NOPASSWD:ALL'
        ssh_authorized_keys:
          - ${local_file.ssh_key_pub.content}
  EOT
}

# Создание дополнительного диска для iscsi
resource "yandex_compute_disk" "iscsi_disk" {
  zone = var.yandex_zone
  size = 10 # Размер диска в гигабайтах
  type = "network-hdd"
}

# Создание виртуальных машин
resource "yandex_compute_instance" "vm_iscsi" {
  depends_on = [
    local_file.cloud_config
  ]
  name        = "iscsi"
  zone        = var.yandex_zone
  platform_id = "standard-v2"
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = var.image_id
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.lab_subnet.id
    nat        = true
    ip_address = var.iscsi_static_ip # Статический IP для iSCS
  }

  metadata = {
    user-data = "${file("./cloud-config.yaml")}"
  }

  labels = {
    environment = "production-laba"
    managered   = "terraform"
    lesson      = "4-iscsi"
  }

  secondary_disk {
    disk_id = yandex_compute_disk.iscsi_disk.id
  }

}

resource "yandex_compute_instance" "vm_nodes" {
  count       = var.node_count
  depends_on  = [local_file.cloud_config]
  name        = "node${count.index + 1}"
  zone        = var.yandex_zone
  platform_id = "standard-v2"
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = var.image_id
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.lab_subnet.id
    nat        = true
    ip_address = var.nodes_static_ips[count.index]
  }

  metadata = {
    user-data = "${file("./cloud-config.yaml")}"
  }

  labels = {
    environment = "production-laba"
    managered   = "terraform"
    lesson      = "4-iscsi"
  }
}


# Создание файла hosts с указанием пути к приватному ключу SSH
resource "local_file" "hosts_file" {
  filename = "${path.module}/hosts"
  content  = <<-EOT
    [iscsi]
    ${yandex_compute_instance.vm_iscsi.network_interface[0].nat_ip_address} ansible_ssh_user=ubuntu ansible_ssh_private_key_file="${path.module}/id_rsa"

    [nodes]
    %{for idx in range(var.node_count)~}

    ${yandex_compute_instance.vm_nodes[idx].network_interface[0].nat_ip_address} ansible_ssh_user=ubuntu ansible_ssh_private_key_file="${path.module}/id_rsa"
    %{endfor~}

    %{for idx in range(var.node_count)~}

    [node${idx + 1}]
    ${yandex_compute_instance.vm_nodes[idx].network_interface[0].nat_ip_address} ansible_ssh_user=ubuntu ansible_ssh_private_key_file="${path.module}/id_rsa"
    %{endfor~}
  EOT
}

# Определение ресурса null_resource для провижининга
resource "null_resource" "ansible_provisioner_server" {
  # Этот ресурс не представляет собой реальный ресурс, а используется только для провижионинга
  # Мы указываем зависимость от других ресурсов, чтобы Terraform выполнил этот ресурс после создания других ресурсов
  depends_on = [
    yandex_compute_instance.vm_iscsi
  ]
  provisioner "local-exec" {
    command = "sleep 60" # Пауза в 60 секунд (1 минута)
  }
  # Команда, которая будет выполнена локально после создания ресурсов
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i '${path.module}/hosts' -l iscsi ${path.module}/setup_iscsi.yml"
  }
}

# Определение ресурса null_resource для провижининга
resource "null_resource" "ansible_provisioner_server2" {
  # Этот ресурс не представляет собой реальный ресурс, а используется только для провижионинга
  # Мы указываем зависимость от других ресурсов, чтобы Terraform выполнил этот ресурс после создания других ресурсов
  depends_on = [
    yandex_compute_instance.vm_nodes
  ]
  provisioner "local-exec" {
    command = "sleep 60" # Пауза в 60 секунд (1 минута)
  }
  # Команда, которая будет выполнена локально после создания ресурсов
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i '${path.module}/hosts' -l nodes ${path.module}/setup_gfs2.yml"
  }
}
