mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_vm" {
    defaults = {
      id = "test-vm-123"
      name = "test-vm"
      node_name = "pve"
      vm_id = 1234
    }
  }
  
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "test-cloud-config"
    }
  }
}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "mock-password-123"
    }
  }
}

variables {
  proxmox_node = "pve"
  vm_template = "9000"
  cpu_cores = "2"
  memory_mb = "2048"
  disk_size = "32"
  datastore = "local-lvm"
  network_bridge = "vmbr0"
}

run "validate_vm_creation_with_numeric_template" {
  command = plan
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.clone[0].vm_id == 9000
    error_message = "VM template ID should be numeric 9000"
  }
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.cpu[0].cores == 2
    error_message = "CPU cores should be 2"
  }
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.memory[0].dedicated == 2048
    error_message = "Memory should be 2048 MB"
  }
}

run "validate_resources_exist" {
  command = plan
  
  assert {
    condition = proxmox_virtual_environment_vm.dev != null
    error_message = "Proxmox VM resource should exist"
  }
  
  assert {
    condition = proxmox_virtual_environment_file.cloud_config != null
    error_message = "Cloud-init config should exist"
  }
  
  assert {
    condition = random_password.vm_password != null
    error_message = "Random password should exist"
  }
}

run "validate_default_configuration" {
  command = plan
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.cpu[0].cores == 2
    error_message = "Default CPU cores should be 2"
  }
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.memory[0].dedicated == 2048
    error_message = "Default memory should be 2048 MB"
  }
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.node_name == "pve"
    error_message = "Default node should be 'pve'"
  }
}

run "validate_vm_structure" {
  command = plan
  
  assert {
    condition = can(regex("^coder-", proxmox_virtual_environment_vm.dev.name))
    error_message = "VM name should start with 'coder-'"
  }
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.network_device[0].bridge == "vmbr0"
    error_message = "Default network bridge should be vmbr0"
  }
  
  assert {
    condition = proxmox_virtual_environment_vm.dev.disk[0].size == 32
    error_message = "Default disk size should be 32 GB"
  }
}