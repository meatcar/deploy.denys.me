# __generated__ by OpenTofu
# Please review these resources and move them into your main configuration files.

# __generated__ by OpenTofu from "ocid1.vcn.oc1.ca-toronto-1.amaaaaaanvwzxkqajgltohabkxvuk3skooqmllqve3vxsokezi4ingzclrta"
resource "oci_core_vcn" "chunkymonkey" {
  cidr_block     = "10.0.0.0/16"
  cidr_blocks    = ["10.0.0.0/16"]
  compartment_id = var.oci_compartment_ocid
  defined_tags = {
    "Oracle-Tags.CreatedBy" = "default/cloud.oracle.com@denys.me"
    "Oracle-Tags.CreatedOn" = "2023-10-20T16:37:26.863Z"
  }
  display_name                     = "vcn-20231020-1234"
  dns_label                        = "vcn10201237"
  freeform_tags                    = {}
  ipv6private_cidr_blocks          = []
  is_ipv6enabled                   = false
  is_oracle_gua_allocation_enabled = null
  security_attributes              = {}
}

# __generated__ by OpenTofu from "ocid1.internetgateway.oc1.ca-toronto-1.aaaaaaaanhehipbgjywe32ktkxhyarbdht7khlv73uezqsxjfvt6dmfc32lq"
resource "oci_core_internet_gateway" "chunkymonkey" {
  compartment_id = var.oci_compartment_ocid
  defined_tags = {
    "Oracle-Tags.CreatedBy" = "default/cloud.oracle.com@denys.me"
    "Oracle-Tags.CreatedOn" = "2023-10-20T16:37:27.671Z"
  }
  display_name   = "Internet Gateway vcn-20231020-1234"
  enabled        = true
  freeform_tags  = {}
  route_table_id = null
  vcn_id         = "ocid1.vcn.oc1.ca-toronto-1.amaaaaaanvwzxkqajgltohabkxvuk3skooqmllqve3vxsokezi4ingzclrta"
}

# __generated__ by OpenTofu from "ocid1.subnet.oc1.ca-toronto-1.aaaaaaaa72qczgbljn2ehwkgz5lr2bpbztrjkuxw2g7prhu7rpgciobnioqq"
resource "oci_core_subnet" "chunkymonkey" {
  availability_domain = null
  cidr_block          = "10.0.0.0/24"
  compartment_id      = "ocid1.tenancy.oc1..aaaaaaaa3p7lj2mdp6zk6iv472kkv3h4rj4edlnib3izjzpisxwp4bxjvqma"
  defined_tags = {
    "Oracle-Tags.CreatedBy" = "default/cloud.oracle.com@denys.me"
    "Oracle-Tags.CreatedOn" = "2023-10-20T16:37:28.921Z"
  }
  dhcp_options_id            = "ocid1.dhcpoptions.oc1.ca-toronto-1.aaaaaaaavoig3d7tofrh4vcj2fyn6momtj7eh3gv3xokbdxit5mg5cfi4mrq"
  display_name               = "subnet-20231020-1234"
  dns_label                  = "subnet10201237"
  freeform_tags              = {}
  ipv4cidr_blocks            = ["10.0.0.0/24"]
  ipv6cidr_block             = null
  ipv6cidr_blocks            = []
  prohibit_internet_ingress  = false
  prohibit_public_ip_on_vnic = false
  route_table_id             = "ocid1.routetable.oc1.ca-toronto-1.aaaaaaaaep4mgi6rtysixrokk6yi242hwo2fwghaxjbsgjvzgycn3ivlq6ja"
  security_list_ids          = ["ocid1.securitylist.oc1.ca-toronto-1.aaaaaaaaujt65tqgvspjqldrdsqryfrxkr4m76oikggrah4rfjh2izjt7bla"]
  vcn_id                     = "ocid1.vcn.oc1.ca-toronto-1.amaaaaaanvwzxkqajgltohabkxvuk3skooqmllqve3vxsokezi4ingzclrta"
}

# __generated__ by OpenTofu from "ocid1.securitylist.oc1.ca-toronto-1.aaaaaaaaujt65tqgvspjqldrdsqryfrxkr4m76oikggrah4rfjh2izjt7bla"
resource "oci_core_security_list" "chunkymonkey" {
  compartment_id = var.oci_compartment_ocid
  defined_tags = {
    "Oracle-Tags.CreatedBy" = "default/cloud.oracle.com@denys.me"
    "Oracle-Tags.CreatedOn" = "2023-10-20T16:37:26.863Z"
  }
  display_name  = "Default Security List for vcn-20231020-1234"
  freeform_tags = {}
  vcn_id        = "ocid1.vcn.oc1.ca-toronto-1.amaaaaaanvwzxkqajgltohabkxvuk3skooqmllqve3vxsokezi4ingzclrta"
  egress_security_rules {
    description      = ""
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }
  ingress_security_rules {
    description = ""
    protocol    = "1"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    stateless   = false
    icmp_options {
      code = -1
      type = 3
    }
  }
  ingress_security_rules {
    description = ""
    protocol    = "1"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    icmp_options {
      code = 4
      type = 3
    }
  }
  ingress_security_rules {
    description = ""
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      max = 22
      min = 22
    }
  }
  ingress_security_rules {
    description = "HTTP"
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 80
      max = 80
    }
  }
  ingress_security_rules {
    description = "HTTPS"
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    tcp_options {
      min = 443
      max = 443
    }
  }
}

# __generated__ by OpenTofu from "ocid1.routetable.oc1.ca-toronto-1.aaaaaaaaep4mgi6rtysixrokk6yi242hwo2fwghaxjbsgjvzgycn3ivlq6ja"
resource "oci_core_route_table" "chunkymonkey" {
  compartment_id = var.oci_compartment_ocid
  defined_tags = {
    "Oracle-Tags.CreatedBy" = "default/cloud.oracle.com@denys.me"
    "Oracle-Tags.CreatedOn" = "2023-10-20T16:37:26.863Z"
  }
  display_name  = "Default Route Table for vcn-20231020-1234"
  freeform_tags = {}
  vcn_id        = "ocid1.vcn.oc1.ca-toronto-1.amaaaaaanvwzxkqajgltohabkxvuk3skooqmllqve3vxsokezi4ingzclrta"
  route_rules {
    description       = ""
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = "ocid1.internetgateway.oc1.ca-toronto-1.aaaaaaaanhehipbgjywe32ktkxhyarbdht7khlv73uezqsxjfvt6dmfc32lq"
    route_type        = "STATIC"
  }
}

# __generated__ by OpenTofu from "ocid1.instance.oc1.ca-toronto-1.an2g6ljrnvwzxkqcijjitq2odvbnmau4icu2jvoctdllqe5ux2omw2khld4q"
resource "oci_core_instance" "chunkymonkey" {
  async                      = null
  availability_domain        = "RFWK:CA-TORONTO-1-AD-1"
  capacity_reservation_id    = null
  cluster_placement_group_id = null
  compartment_id             = "ocid1.tenancy.oc1..aaaaaaaa3p7lj2mdp6zk6iv472kkv3h4rj4edlnib3izjzpisxwp4bxjvqma"
  compute_cluster_id         = null
  dedicated_vm_host_id       = null
  defined_tags = {
    "Oracle-Tags.CreatedBy" = "default/cloud.oracle.com@denys.me"
    "Oracle-Tags.CreatedOn" = "2023-10-25T03:22:27.799Z"
  }
  display_name                        = "chunkymonkey"
  extended_metadata                   = {}
  fault_domain                        = "FAULT-DOMAIN-3"
  freeform_tags                       = {}
  instance_configuration_id           = null
  ipxe_script                         = null
  is_ai_enterprise_enabled            = null
  is_pv_encryption_in_transit_enabled = null
  metadata = {
    ssh_authorized_keys = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcq01gh2tn/+hcm75N3LnS003mUBjXcT6qNndMhObPO"
  }
  preserve_boot_volume                    = null
  preserve_data_volumes_created_at_launch = null
  security_attributes                     = {}
  shape                                   = "VM.Standard.A1.Flex"
  state                                   = "RUNNING"
  update_operation_constraint             = null
  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false
    plugins_config {
      desired_state = "DISABLED"
      name          = "Vulnerability Scanning"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute RDMA GPU Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Auto-Configuration"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Compute HPC RDMA Authentication"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Block Volume Management"
    }
    plugins_config {
      desired_state = "DISABLED"
      name          = "Bastion"
    }
  }
  availability_config {
    is_live_migration_preferred = false
    recovery_action             = "RESTORE_INSTANCE"
  }
  create_vnic_details {
    assign_ipv6ip             = false
    assign_private_dns_record = false
    assign_public_ip          = "true"
    defined_tags = {
      "Oracle-Tags.CreatedBy" = "default/cloud.oracle.com@denys.me"
      "Oracle-Tags.CreatedOn" = "2023-10-25T03:22:27.947Z"
    }
    display_name           = "chunkymonkey"
    freeform_tags          = {}
    hostname_label         = "chunkymonkey"
    nsg_ids                = []
    private_ip             = "10.0.0.173"
    private_ip_id          = ""
    security_attributes    = {}
    skip_source_dest_check = false
    subnet_cidr            = ""
    subnet_id              = "ocid1.subnet.oc1.ca-toronto-1.aaaaaaaa72qczgbljn2ehwkgz5lr2bpbztrjkuxw2g7prhu7rpgciobnioqq"
    vlan_id                = ""
  }
  instance_options {
    are_legacy_imds_endpoints_disabled = false
  }
  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    is_consistent_volume_naming_enabled = true
    is_pv_encryption_in_transit_enabled = true
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
  }
  shape_config {
    baseline_ocpu_utilization = ""
    local_volume_size_in_gbs  = 0
    memory_in_gbs             = 24
    nvmes                     = 0
    ocpus                     = 4
    resource_management       = ""
    vcpus                     = 4
  }
  source_details {
    boot_volume_size_in_gbs         = "200"
    boot_volume_vpus_per_gb         = "20"
    is_preserve_boot_volume_enabled = false
    kms_key_id                      = ""
    source_id                       = "ocid1.image.oc1.ca-toronto-1.aaaaaaaav4b5wgn6jyzz2wj4n6vbrfp4qxyxjjg3z5u7cyziypsw2hbcrm3a"
    source_type                     = "image"
  }
}
