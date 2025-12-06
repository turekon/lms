terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Configuración del proveedor (token vía variable de entorno TF_VAR_do_token)
provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.spaces_access_key   
  spaces_secret_key = var.spaces_secret_key   
}

# Buscamos la llave en DigitalOcean por su nombre
data "digitalocean_ssh_key" "mi_llave" {
  name = "asus_rog_wsl" # <--- PON AQUÍ EL NOMBRE EXACTO QUE USASTE EN DIGITALOCEAN
}

variable "do_token" {} # Se espera que el valor se proporcione a través de TF_VAR_do_token o un archivo .tfvars
variable "spaces_access_key" {}
variable "spaces_secret_key" { sensitive = true }
variable "region" { default = "nyc3" } # Cambiar a la región más cercana

# variable para el entorno
variable "environment" {
  description = "El entorno de despliegue: 'test' o 'prod'"
  type        = string
}

# variable para los tags
variable "project_tags" {
  default = ["lms"]
}

# variable para el nombre del proyecto
variable "project_name" {
  default = "lms"
}

# Crear el Proyecto en DigitalOcean automáticamente
resource "digitalocean_project" "env_project" {
  name        = "${var.project_name} - ${var.environment} - project"
  description = "Infraestructura para el entorno de ${var.environment}"
  purpose     = "Web Application"
  environment = var.environment == "prod" ? "Production" : "Development"
}

# Asignar los recursos a ese proyecto
# DigitalOcean requiere este recurso "puente" para meter cosas en carpetas/proyectos
resource "digitalocean_project_resources" "project_assignment" {
  project = digitalocean_project.env_project.id
  
  resources = [
    digitalocean_droplet.lms_node.urn,    
    digitalocean_floating_ip.lms_ip.urn    
  ]
}

# Red Privada (VPC) para seguridad
resource "digitalocean_vpc" "mvp_network" {
  name   = "vpc-${var.project_name}-${var.environment}" # Nombre único por ambiente
  region = var.region
}

# 4. Servidor LMS (Droplet)
# Un LMS puede consumir bastante RAM. Se selecciona 8GB RAM para estabilidad.
resource "digitalocean_droplet" "lms_node" {
  image    = "fedora-42-x64"
  name     = "srv-${var.project_name}-${var.environment}"
  region   = var.region
  size     = "s-4vcpu-8gb" 
  vpc_uuid = digitalocean_vpc.mvp_network.id
  backups  = true
  ssh_keys = [data.digitalocean_ssh_key.mi_llave.id]  
  tags     = [var.project_name, "rol-lms", var.environment]
}

# 6. IPs Públicas Estáticas (Floating IPs)
resource "digitalocean_floating_ip" "lms_ip" {
  region = var.region
}

# 7. Asignación de IPs a los Droplets
resource "digitalocean_floating_ip_assignment" "lms_ip_assign" {
  ip_address = digitalocean_floating_ip.lms_ip.ip_address
  droplet_id = digitalocean_droplet.lms_node.id
}

# 8. Firewall para los servidores web
resource "digitalocean_firewall" "web_firewall" {
  name = "${var.project_name}-fw-${var.environment}" # Nombre único que incluye proyecto y entorno

  # Aplicar este firewall al Droplet del LMS
  droplet_ids = [
    digitalocean_droplet.lms_node.id    
  ]

  # Reglas de entrada: Permitir SSH, HTTP y HTTPS desde cualquier lugar
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22" # SSH
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80" # HTTP
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443" # HTTPS
    source_addresses = ["0.0.0.0/0", "::/0"]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8000" # HTTP
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Reglas de salida: Permitir todo el tráfico saliente para actualizaciones, etc.
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# 9. Salidas (Outputs) para conexión rápida
output "lms_ip" {
  value = digitalocean_floating_ip.lms_ip.ip_address
}
