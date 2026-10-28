# Create a dedicated resource group for this lab.
resource "azurerm_resource_group" "lab" {
  name     = "${var.project_name}-rg"
  location = var.location

  tags = {
    project     = var.project_name
    environment = "lab"
    managed_by  = "terraform"
  }
}

# Create a private address space for the VM.
resource "azurerm_virtual_network" "lab" {
  name                = "${var.project_name}-vnet"
  address_space       = ["10.50.0.0/16"]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

# Place the Ubuntu VM in a dedicated subnet.
resource "azurerm_subnet" "lab" {
  name                 = "${var.project_name}-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.50.1.0/24"]
}

# Permit inbound SSH only from the trusted public IPv4 address.
# Azure's default NSG rules deny other unsolicited inbound traffic.
resource "azurerm_network_security_group" "lab" {
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "Allow-SSH-From-Trusted-IP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.trusted_ssh_cidr
    destination_address_prefix = "*"
  }

  tags = {
    project = var.project_name
  }
}

# Assign a public IP so Ansible can reach the VM over SSH.
resource "azurerm_public_ip" "lab" {
  name                = "${var.project_name}-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    project = var.project_name
  }
}

# Connect the VM to the subnet and public IP.
resource "azurerm_network_interface" "lab" {
  name                = "${var.project_name}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab.id
  }

  tags = {
    project = var.project_name
  }
}

# Apply the SSH network security group to the VM's network interface.
resource "azurerm_network_interface_security_group_association" "lab" {
  network_interface_id      = azurerm_network_interface.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

# Create the Ubuntu 22.04 LTS virtual machine.
resource "azurerm_linux_virtual_machine" "lab" {
  name                = "${var.project_name}-vm"
  computer_name       = "linux-hardening"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  size                = var.vm_size
  admin_username      = "azureuser"

  # Use SSH public-key authentication; do not configure a VM password.
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.lab.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.public_key_path))
  }

  # Use a 30 GiB standard locally redundant managed OS disk.
  os_disk {
    name                 = "${var.project_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  # Select the Canonical Ubuntu Server 22.04 LTS Gen2 image.
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    project     = var.project_name
    environment = "lab"
    managed_by  = "terraform"
  }
}
