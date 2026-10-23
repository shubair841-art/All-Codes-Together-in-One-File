
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.10.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "admin_password" {}

resource "azurerm_resource_group" "shk1" {
  name     = "rg-shubair-1"
  location = "Central India"
}

resource "azurerm_storage_account" "str1" {
  depends_on               = [azurerm_resource_group.shk1]
  name                     = "storageshubair11x"
  resource_group_name      = "rg-shubair-1"
  location                 = "Central India"
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "ctr1" {
  depends_on            = [azurerm_storage_account.str1]
  name                  = "upload"
  storage_account_id    = azurerm_storage_account.str1.id
  container_access_type = "private"
}

resource "azurerm_virtual_network" "vnet" {
  depends_on          = [azurerm_resource_group.shk1]
  name                = "vnet-shubair"
  location            = azurerm_resource_group.shk1.location
  resource_group_name = azurerm_resource_group.shk1.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "snet" {
  depends_on           = [azurerm_virtual_network.vnet]
  name                 = "snet-shubair"
  resource_group_name  = azurerm_resource_group.shk1.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "appgw_snet" {
  name                 = "snet-appgateway"
  resource_group_name  = azurerm_resource_group.shk1.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "nic" {
  depends_on          = [azurerm_resource_group.shk1]
  name                = "nic-shubair"
  location            = "Central India"
  resource_group_name = "rg-shubair-1"

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.snet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                  = "vm-shubair"
  location              = "Central India"
  resource_group_name   = "rg-shubair-1"
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_B4ls_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "linux"
    admin_username = "linuxadmin"
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

resource "azurerm_public_ip" "pip" {
  depends_on          = [azurerm_resource_group.shk1]
  name                = "PublicIPForLB"
  location            = "Central India"
  resource_group_name = "rg-shubair-1"
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "appgw_pip" {
  name                = "PublicIPForAppGateway"
  location            = azurerm_resource_group.shk1.location
  resource_group_name = azurerm_resource_group.shk1.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "lb" {
  depends_on          = [azurerm_resource_group.shk1]
  name                = "TestLoadBalancer"
  location            = "Central India"
  resource_group_name = "rg-shubair-1"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.pip.id
  }
}

locals {
  backend_address_pool_name      = "azurerm_virtual_network.vm-shubair.name-beap"
  frontend_port_name             = "azurerm_virtual_network.vm-shubair.name-feport"
  frontend_ip_configuration_name = "azurerm_virtual_network.vm-shubair.name-feip"
  http_setting_name              = "azurerm_virtual_network.vm-shubair.name-be-htst"
  listener_name                  = "azurerm_virtual_network.vm-shubair.name-httplstn"
  request_routing_rule_name      = "azurerm_virtual_network.vm-shubair.name-rqrt"
  redirect_configuration_name    = "azurerm_virtual_network.vm-shubair.name-rdrcfg"
}

resource "azurerm_application_gateway" "network" {
  depends_on          = [azurerm_resource_group.shk1]
  name                = "appgateway-shubair"
  resource_group_name = azurerm_resource_group.shk1.name
  location            = azurerm_resource_group.shk1.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name = "my-gateway-ip-configuration"

    # UPDATED: Use the dedicated Application Gateway subnet.
    # WHY: Application Gateway cannot use the subnet shared with the VM.
    subnet_id = azurerm_subnet.appgw_snet.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name = local.frontend_ip_configuration_name

    # UPDATED: Reference the new, dedicated Application Gateway Public IP.
    # WHY: Prevents PublicIPAddressInUse conflict with TestLoadBalancer.
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
}
