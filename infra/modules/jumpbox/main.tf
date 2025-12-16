# -----------------------------------------------------------------------------
# Azure Linux VM (Jumpbox) Module
# -----------------------------------------------------------------------------
# Creates a Linux VM for development/testing with browser support.
# Uses B-series burstable VM for cost-effective dedicated compute.
# -----------------------------------------------------------------------------

# Generate SSH key pair using azapi_resource_action
resource "azapi_resource_action" "ssh_public_key_gen" {
  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  resource_id = azapi_resource.ssh_public_key.id
  action      = "generateKeyPair"
  method      = "POST"

  response_export_values = ["publicKey", "privateKey"]
}

# SSH Public Key resource in Azure
resource "azapi_resource" "ssh_public_key" {
  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
  name      = "${var.app_name}-jumpbox-ssh-key"
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}"

  body = {}

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Generate random admin username
resource "random_string" "admin_username" {
  length  = 12
  upper   = true
  lower   = true
  special = false
}
# Get current subscription for resource ID construction
data "azurerm_subscription" "current" {}

# Network Interface for the VM (no public IP - accessed via Bastion)
resource "azurerm_network_interface" "jumpbox" {
  name                = "${var.app_name}-jumpbox-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Azure Linux Virtual Machine (Dedicated B-series)
resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                = "${var.app_name}-jumpbox"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = random_string.admin_username.result

  # No eviction_policy or max_bid_price - this is a dedicated VM
  priority = "Regular"

  network_interface_ids = [
    azurerm_network_interface.jumpbox.id,
  ]

  admin_ssh_key {
    username   = random_string.admin_username.result
    public_key = azapi_resource_action.ssh_public_key_gen.output.publicKey
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  # Ubuntu 24.04 LTS (Noble Numbat) with desktop support capability
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Enable boot diagnostics with managed storage
  boot_diagnostics {
    storage_account_uri = null # Uses managed storage account
  }

  # Custom data script to install CLI tools for development
  custom_data = base64encode(<<-EOF
#!/bin/bash
set -ex
exec > /var/log/cloud-init-custom.log 2>&1

echo "Starting Ubuntu 24.04 jumpbox CLI setup at $(date)"

# Update system packages
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install essential CLI tools
echo "Installing essential tools..."
apt-get install -y \
  curl \
  wget \
  git \
  vim \
  htop \
  tmux \
  net-tools \
  dnsutils \
  jq \
  unzip \
  ca-certificates \
  gnupg \
  lsb-release \
  python3 \
  python3-pip \
  python3-venv

# Install Azure CLI
echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install GitHub CLI
echo "Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update
apt-get install -y gh

# Install Terraform CLI
echo "Installing Terraform CLI..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
apt-get update
apt-get install -y terraform

# Install kubectl
echo "Installing kubectl..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
apt-get update
apt-get install -y kubectl

# Install Docker
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker ${random_string.admin_username.result}

# Clean up
apt-get autoremove -y
apt-get clean

echo "Ubuntu 24.04 jumpbox CLI setup complete at $(date)!"
echo "SSH access is ready. Connect via Azure Bastion using SSH."
  EOF
  )

  identity {
    type = "SystemAssigned"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Save private key to local file for documentation purposes
# NOTE: This file should be in .gitignore
resource "local_sensitive_file" "ssh_private_key" {
  content         = azapi_resource_action.ssh_public_key_gen.output.privateKey
  filename        = "${path.root}/../sensitive/jumpbox_ssh_key.pem"
  file_permission = "0600"
}

# -----------------------------------------------------------------------------
# Auto-Shutdown Schedule (7 PM PST / 3 AM UTC next day)
# -----------------------------------------------------------------------------
# Note: Azure stores time in UTC. PST = UTC-8, so 7 PM PST = 3:00 AM UTC (next day)
resource "azurerm_dev_test_global_vm_shutdown_schedule" "jumpbox" {
  virtual_machine_id    = azurerm_linux_virtual_machine.jumpbox.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = "1900" # 7:00 PM in the specified timezone
  timezone              = "Pacific Standard Time"

  notification_settings {
    enabled = false # Set to true and configure webhook/email if notifications needed
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# -----------------------------------------------------------------------------
# Auto-Start Schedule (8 AM PST, Monday-Friday)
# Requires Azure Automation Account with Runbook
# -----------------------------------------------------------------------------
resource "azurerm_automation_account" "jumpbox" {
  name                = "${var.app_name}-jumpbox-automation"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Python3 Runbook to start the VM
# Note: Azure Automation requires Python packages to be imported separately
resource "azurerm_automation_runbook" "start_vm" {
  name                    = "Start-JumpboxVM"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.jumpbox.name
  log_verbose             = false
  log_progress            = false
  runbook_type            = "Python3"

  content = <<-PYTHON
#!/usr/bin/env python3
"""
Start Jumpbox VM Runbook
This runbook starts the VM using the Automation Account's managed identity.
Uses Azure Automation environment variables for authentication.
"""

import json
import os
import sys

# VM Configuration (injected by Terraform)
SUBSCRIPTION_ID = "${data.azurerm_subscription.current.subscription_id}"
RESOURCE_GROUP = "${var.resource_group_name}"
VM_NAME = "${var.app_name}-jumpbox"

def get_automation_token():
    """
    Get access token using Azure Automation's built-in managed identity.
    Uses IDENTITY_ENDPOINT and IDENTITY_HEADER environment variables.
    """
    import urllib.request
    import urllib.error
    
    identity_endpoint = os.environ.get("IDENTITY_ENDPOINT")
    identity_header = os.environ.get("IDENTITY_HEADER")
    
    if not identity_endpoint or not identity_header:
        raise Exception("IDENTITY_ENDPOINT or IDENTITY_HEADER not set. Ensure managed identity is enabled on the Automation Account.")
    
    resource = "https://management.azure.com/"
    token_url = f"{identity_endpoint}?resource={resource}&api-version=2019-08-01"
    
    req = urllib.request.Request(token_url)
    req.add_header("X-IDENTITY-HEADER", identity_header)
    req.add_header("Metadata", "true")
    
    try:
        response = urllib.request.urlopen(req, timeout=30)
        data = json.loads(response.read().decode())
        return data["access_token"]
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        raise Exception(f"Failed to get token: {e.code} {e.reason} - {body}")

def start_vm(access_token):
    """
    Start the VM using Azure REST API.
    """
    import urllib.request
    import urllib.error
    
    url = f"https://management.azure.com/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/{VM_NAME}/start?api-version=2023-07-01"
    
    req = urllib.request.Request(url, data=b"", method="POST")
    req.add_header("Authorization", f"Bearer {access_token}")
    req.add_header("Content-Type", "application/json")
    
    try:
        response = urllib.request.urlopen(req, timeout=60)
        print(f"VM start initiated successfully (status: {response.status})")
        return True
    except urllib.error.HTTPError as e:
        if e.code == 202:
            print(f"VM start initiated successfully (async operation - 202)")
            return True
        body = e.read().decode() if e.fp else ""
        raise Exception(f"Failed to start VM: {e.code} {e.reason} - {body}")

def main():
    print(f"Starting VM: {VM_NAME}")
    print(f"Resource Group: {RESOURCE_GROUP}")
    print(f"Subscription: {SUBSCRIPTION_ID}")
    
    try:
        print("Acquiring access token using managed identity...")
        token = get_automation_token()
        print("Access token acquired successfully")
        
        print("Sending start command to VM...")
        start_vm(token)
        print(f"VM {VM_NAME} start command completed successfully")
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
  PYTHON

  tags = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

# Schedule for weekday mornings (8 AM PST, Monday-Friday)
resource "azurerm_automation_schedule" "weekday_start" {
  name                    = "Weekday-8AM-Start"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.jumpbox.name
  frequency               = "Week"
  interval                = 1
  timezone                = "America/Vancouver" # Pacific Time (PST/PDT)
  # RFC3339 format - Azure uses the timezone setting above to interpret this time
  start_time = "${formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))}T08:00:00Z"
  week_days  = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time] # Ignore changes after initial creation
  }
}

# Link the schedule to the runbook
# Note: Parameters are embedded in the runbook script (Terraform-injected)
resource "azurerm_automation_job_schedule" "start_vm" {
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.jumpbox.name
  schedule_name           = azurerm_automation_schedule.weekday_start.name
  runbook_name            = azurerm_automation_runbook.start_vm.name
}

# Role assignment: Allow Automation Account to start/stop the VM
resource "azurerm_role_assignment" "automation_vm_contributor" {
  scope                = azurerm_linux_virtual_machine.jumpbox.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.jumpbox.identity[0].principal_id
}

