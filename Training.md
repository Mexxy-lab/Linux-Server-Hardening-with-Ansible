# Project 2: Automated Linux Server Hardening

- Let's build this as a recruiter-ready DevOps security project using Terraform for provisioning, Ansible for configuration management, and Ubuntu Server as the operating system.

- We'll support three platforms in separate directories: local Vagrant, AWS, and Azure. The goal is to maintain one reusable hardening playbook so that the security configuration stays consistent regardless of where the Linux server runs.

## Project Architecture

![alt text](Pictures/image.png)

## Repo structure

linux-server-hardening/
├── README.md
├── .gitignore
├── ansible.cfg
├── requirements.yml
│
├── ansible/
│   ├── inventories/
│   │   ├── vagrant/hosts.yml
│   │   ├── aws/hosts.yml
│   │   └── azure/hosts.yml
│   ├── playbooks/
│   │   ├── harden.yml
│   │   └── verify.yml
│   ├── roles/
│   │   └── linux_hardening/
│   │       ├── defaults/main.yml
│   │       ├── tasks/main.yml
│   │       ├── handlers/main.yml
│   │       └── templates/
│   └── group_vars/
│       └── linux_servers.yml
│
├── vagrant/
│   ├── Vagrantfile
│   └── README.md
│
├── aws/
│   └── terraform/
│       ├── versions.tf
│       ├── providers.tf
│       ├── variables.tf
│       ├── network.tf
│       ├── compute.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
│
├── azure/
│   └── terraform/
│       ├── versions.tf
│       ├── providers.tf
│       ├── variables.tf
│       ├── network.tf
│       ├── compute.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
│
├── scripts/
│   ├── validate.sh
│   └── hardening-report.sh
│
└── docs/
    ├── architecture.md
    ├── security-baseline.md
    └── testing.md

- Important design decision: Ansible will own the OS-level security settings
- Terraform will own the infrastructure, networking, and cloud access boundaries
- This separation makes the project easier to maintain and demonstrates a clear understanding of infrastructure versus configuration management

## Security Baseline

```bash
Control                     Implementation                                                                              Validation

SSH                         Key-based login; disable password authentication after key access is confirmed              Test key login and confirm password login is rejected
Admin access                Dedicated linuxadmin account with controlled sudo privileges                                Check group membership and sudo policy
Root Access                 Disable direct root SSH login                                                               Inspect effective SSH configuration
Firewall                    UFW with default-deny inbound and allow outbound                                            Verify permitted ports and firewall status
Patching                    Install security updates; make reboot behavior configurable                                 Check package and reboot status
Time                        systemd-timesyncd or the supported Ubuntu time service                                      Check synchronization status
Idempotency                 Re-run the Ansible playbook                                                                 Confirm the second run reports no unexpected changes
Verification                Run explicit security checks after hardening                                                Generate a report of pass/fail results
```

## Which user does ansible use

```bash
Environment                 SSH user                        SSH private key                           Purpose

Local Vagrant VM            vagrant                         Vagrant-generated private key             Initial connection to your local VM
AWS EC2                     ubuntu                          ~/.ssh/linux_hardening_ed25519            Initial connection to the Ubuntu EC2 instance
After hardening             linuxadmin is created           ~/.ssh/linux_hardening_ed25519            Dedicated administrative account for future access
```

## Build plan

```text
Phase 1 — Foundation
Create the repository, Python virtual environment, Ansible configuration, and shared hardening role. Validate the role syntax before provisioning any VM.

Phase 2 — Local lab with Vagrant
Start with one Ubuntu VM. Apply the Ansible role, test SSH and firewall behavior, then run the playbook again to test idempotency.

Phase 3 — AWS
Use Terraform to provision an EC2 instance, network controls, SSH access, and an encrypted root volume. Apply the same Ansible role.

Phase 4 — Azure
Provision an Ubuntu VM and network security rules using Terraform. Reuse the same Ansible role and verification checks.

Phase 5 — Evidence and documentation
Generate validation reports, document the architecture and security decisions, capture successful test results, and prepare the GitHub README and LinkedIn portfolio entry
```

## Establish local files first

```bash
# Navigate to your Projects directory.
mkdir -p ~/Projects
cd ~/Projects

# Create the new repository directory only if it does not exist.
mkdir -p linux-server-hardening
cd linux-server-hardening

# Create the initial project layout.
mkdir -p \
  ansible/inventories/{vagrant,aws,azure} \
  ansible/playbooks \
  ansible/roles/linux_hardening/{defaults,tasks,handlers,templates} \
  ansible/group_vars \
  vagrant \
  aws/terraform \
  azure/terraform \
  scripts \
  docs

# Check the installed tools before choosing installation steps.
printf '\n--- Operating system ---\n'
cat /etc/os-release | head -n 6

printf '\n--- Python ---\n'
python3 --version

printf '\n--- Ansible ---\n'
ansible --version 2>/dev/null || echo "Ansible is not installed or not on PATH"

printf '\n--- Terraform ---\n'
terraform version 2>/dev/null || echo "Terraform is not installed or not on PATH"

printf '\n--- Vagrant ---\n'
vagrant --version 2>/dev/null || echo "Vagrant is not installed or not on PATH"

printf '\n--- VirtualBox ---\n'
VBoxManage --version 2>/dev/null || echo "VirtualBox CLI is not available"

printf '\n--- Azure CLI ---\n'
az version --output table 2>/dev/null || echo "Azure CLI is not installed or not on PATH"

printf '\n--- AWS CLI ---\n'
aws --version 2>/dev/null || echo "AWS CLI is not installed or not on PATH"

# Show the directories created for the project.
find . -maxdepth 4 -type d | sort
```

## Create the project configuration

```bash
# Create and activate an isolated Python environment for this project.
python3 -m venv .venv
source .venv/bin/activate

# Upgrade the packaging tools inside the virtual environment.
python3 -m pip install --upgrade pip

# Install Ansible and the tools we will use to validate the project.
python3 -m pip install ansible-core ansible-lint

# Confirm that the project-local tools are active.
which ansible
ansible --version
ansible-lint --version
```

## Create the ansible.cfg file

```bash
cat > ansible.cfg <<'EOF'
# Keep Ansible configuration local to this repository.
[defaults]
inventory = ansible/inventories/vagrant/hosts.yml
roles_path = ansible/roles
host_key_checking = True
retry_files_enabled = False
interpreter_python = auto_silent

# Avoid gathering facts unnecessarily when a play does not require them.
# Individual playbooks can still enable fact gathering explicitly.
gathering = smart

[privilege_escalation]
# Administrative tasks will use sudo on the Linux target.
become = False
become_method = sudo
become_user = root
become_ask_pass = False
EOF
```

## Create requirements.yml file

```bash
cat > requirements.yml <<'EOF'
---
# Declare external Ansible collections here as the project grows.
# The initial Linux hardening role uses built-in Ansible modules only.
collections: []
roles: []
EOF
```

## Create shared security baseline

```bash
cat > ansible/group_vars/linux_servers.yml <<'EOF'
---
# Shared security baseline for Ubuntu Linux servers on all three platforms.

# Use a dedicated, non-root account for administration.
linux_admin_user: linuxadmin
linux_admin_shell: /bin/bash

# SSH hardening. The role will verify key access before disabling passwords.
ssh_port: 22
ssh_password_authentication: "no"
ssh_permit_root_login: "no"
ssh_pubkey_authentication: "yes"

# UFW policy: block unsolicited inbound traffic and permit outbound traffic.
ufw_default_incoming_policy: deny
ufw_default_outgoing_policy: allow

# SSH is the only inbound service required for the initial lab.
# Cloud security groups / NSGs must also restrict this port to trusted sources.
ufw_allowed_tcp_ports:
  - "{{ ssh_port }}"

# Install security updates without automatically forcing an immediate reboot.
security_updates_enabled: true
automatic_reboot_enabled: false

# Use the Ubuntu systemd time synchronization service where available.
time_sync_service: systemd-timesyncd
EOF

- This baseline intentionally leaves automatic reboots disabled. Reboots should be scheduled and verified rather than triggered unexpectedly during a remote hardening run.
```

## Create hardnening role

- Before changing SSH or firewall settings, we'll make the role validate its prerequisites. This helps avoid accidentally locking ourselves out of the server.

```bash
cat > ansible/roles/linux_hardening/defaults/main.yml <<'EOF'
---
# Defaults can be overridden by inventory or group variables.

linux_admin_user: linuxadmin
linux_admin_shell: /bin/bash

ssh_port: 22
ssh_password_authentication: "no"
ssh_permit_root_login: "no"
ssh_pubkey_authentication: "yes"

ufw_default_incoming_policy: deny
ufw_default_outgoing_policy: allow
ufw_allowed_tcp_ports:
  - "{{ ssh_port }}"

security_updates_enabled: true
automatic_reboot_enabled: false
time_sync_service: systemd-timesyncd
EOF
```

## Create ansible/roles/linux_hardening/tasks/main.yml

```bash
cat > ansible/roles/linux_hardening/tasks/main.yml <<'EOF'
---
# Phase 1: verify the target before applying security changes.

- name: Confirm that the target is Ubuntu
  ansible.builtin.assert:
    that:
      - ansible_distribution == "Ubuntu"
      - ansible_service_mgr == "systemd"
    fail_msg: >-
      This baseline expects Ubuntu with systemd. Stop and review the target
      operating system before applying the hardening role.

- name: Confirm that the SSH port is valid
  ansible.builtin.assert:
    that:
      - ssh_port | int >= 1
      - ssh_port | int <= 65535
    fail_msg: "ssh_port must be a valid TCP port."

# We will add the account, SSH, firewall, patching, and time-sync tasks
# in controlled stages after verifying connectivity to the first VM.
EOF
```

## Create the initial playbook ansible/playbooks/harden.yml

```bash
cat > ansible/playbooks/harden.yml <<'EOF'
---
- name: Apply the Linux server hardening baseline
  hosts: linux_servers
  become: true
  gather_facts: true

  # Keep privilege escalation explicit and limit the first run to checks.
  roles:
    - linux_hardening
EOF

- This is a deliberately small first version. We'll add the actual security controls incrementally and test each change on the local VM before applying the role in AWS or Azure.
```

## Create the initial vagrant inventory host file

```bash
cat > ansible/inventories/vagrant/hosts.yml <<'EOF'
---
all:
  children:
    linux_servers:
      hosts:
        Linux-hardening-vm:
          # Vagrant forwards the VM's SSH port to localhost:2222.
          ansible_host: 127.0.0.1
          ansible_port: 2222

          # Use the default Vagrant account and its private key.
          ansible_user: vagrant
          ansible_ssh_private_key_file: "{{ playbook_dir }}/../../../../vagrant/.vagrant/machines/Linux-hardening-vm/virtualbox/private_key"
EOF

- Test the playbook inventory host file 

ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  --syntax-check \
  ansible/playbooks/harden.yml
```

## Create the Vagrant file for deploying the local VM

```bash
cat > vagrant/Vagrantfile <<'EOF'
VAGRANTFILE_API_VERSION = "2"

$script_create_swapfile = <<-SCRIPT
#!/bin/sh

swapsize=2080

grep -q "/swapfile" /etc/fstab

if [ $? -ne 0 ]; then
    echo "swapfile not found. Adding swapfile."

    fallocate -l ${swapsize}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    echo "/swapfile none swap defaults 0 0" >> /etc/fstab

    echo "✅ Swapfile created successfully."
else
    echo "✅ Swapfile already exists. No changes made."
fi

echo
echo "==================== SWAP INFORMATION ===================="

cat /proc/swaps

echo
cat /proc/meminfo | grep Swap

echo "==========================================================="
SCRIPT

vm_machines = [
    {
        :name => "Linux-hardening-vm",
        :ip   => "192.168.1.130",
    },
    # {
    #     :name => "np-mysql-lvmv9-worker001",
    #     :ip   => "192.168.1.131",
    # },
    # {
    #     :name => "np-mariadb-lvmv9-worker002",
    #     :ip   => "192.168.1.132",
    # },
]

Vagrant.configure("2") do |config|

    config.vm.box = "almalinux/9"

    config.disksize.size = "70GB"

    config.vm.provider "virtualbox" do |v|
        v.memory = 3072
        v.cpus   = 3
    end

    config.vm.synced_folder ".", "/vagrant", disabled: true

    vm_machines.each do |vm_machine|

        config.vm.define vm_machine[:name] do |vm|

            vm.vm.hostname = vm_machine[:name]

            vm.vm.network "public_network",
                ip: vm_machine[:ip]

            vm.vm.provision "shell",
                inline: $script_create_swapfile

        end
    end
end
EOF

- Start the VM 
vagrant.exe up --provider=virtualbox
```

## Verify SSH login from WSL after deploying the local VM

```bash
# Resolve the actual absolute path to the Vagrant private key.
KEY_PATH="$(realpath vagrant/.vagrant/machines/Linux-hardening-vm/virtualbox/private_key)"

# Verify that the key exists and its permissions are restrictive.
test -f "$KEY_PATH" && echo "Private key exists: $KEY_PATH"
chmod 600 "$KEY_PATH"

# Update the inventory to use the absolute path instead of a Jinja expression.
sed -i \
  "s|ansible_ssh_private_key_file:.*|ansible_ssh_private_key_file: \"$KEY_PATH\"|" \
  ansible/inventories/vagrant/hosts.yml

# Log in directly to the Ubuntu VM through the forwarded SSH port.
ssh -i "$KEY" \
  -p 2222 \
  -o IdentitiesOnly=yes \
  vagrant@127.0.0.1

ssh -i .vagrant/machines/Linux-hardening-vm/virtualbox/private_key \
  -o StrictHostKeyChecking=no \
  vagrant@192.168.1.130

# Confirm the operating system and version.
cat /etc/os-release

# Confirm the current user.
whoami

# Confirm the kernel.
uname -r

# Check available disk space and memory.
df -h /
free -h
```

## Test ansible connectivity

```bash
# Test Ansible connectivity.
ansible linux_servers \
  -i ansible/inventories/vagrant/hosts.yml \
  -m ansible.builtin.ping

# Confirm the remote distribution.
ansible linux_servers \
  -i ansible/inventories/vagrant/hosts.yml \
  -m ansible.builtin.setup \
  -a 'filter=ansible_distribution*'
  ```

## Establish the hardening sequence

- We'll implement these controls in order:

1. Preflight checks: verify Ubuntu, systemd, SSH settings, and privilege escalation.
2. Administrative access: create a dedicated linuxadmin account and install its public key.
3. System maintenance: update packages and install required security utilities.
4. Time synchronization: ensure a supported time service is enabled.
5. Firewall: configure UFW to allow SSH before enabling incoming-deny rules.
6. SSH hardening: disable root login and password authentication only after key-based access has been tested.
7. Validation: confirm services, firewall rules, SSH configuration, and idempotency.

- Security note: We must not disable password authentication until we have installed and tested a public key for linuxadmin.
- The current successful connection uses the Vagrant account and its private key; that alone does not prove the new administrator account will work.

## Create a dedicated public key for the admin

```bash
ls -l ~/.ssh/*.pub 2>/dev/null || true

ssh-keygen -t ed25519 \
  -f ~/.ssh/linux_hardening_ed25519 \
  -C "linux-server-hardening-admin"
  ```

## Confirm the pub-key setting is present

```bash
# Confirm that the public key exists.
test -f "$HOME/.ssh/linux_hardening_ed25519.pub" \
  && echo "Public key found." \
  || echo "ERROR: Public key not found."

# Display the public key so you can inspect it if needed.
# This is safe to display; do not display the private key.
cat "$HOME/.ssh/linux_hardening_ed25519.pub"
```

## Store the administrator password hash securely

- We'll give the linuxadmin a password hash so its account is not dependent on a locked or passwordless account configuration.
- SSH will ultimately use your Ed25519 key, not password authentication.

```bash
# Create a password hash without saving the plaintext password in a file.
read -rsp "Set a temporary linuxadmin password: " ADMIN_PASSWORD
printf '\n'
ADMIN_HASH="$(printf '%s' "$ADMIN_PASSWORD" | openssl passwd -6 -stdin)"
unset ADMIN_PASSWORD

# Encrypt the hash with Ansible Vault and save it as a protected variable.
# You will be prompted to create an Ansible Vault password.
ansible-vault encrypt_string \
  --vault-id @prompt \
  --name linux_admin_password_hash \
  "$ADMIN_HASH" > ansible/group_vars/vault.yml

# Clear the hash from the current shell variable.
unset ADMIN_HASH

# Ensure the encrypted vault file is not accidentally committed to Git.
grep -qxF 'ansible/group_vars/vault.yml' .gitignore \
  || echo 'ansible/group_vars/vault.yml' >> .gitignore

# Verify that the vault file exists without printing its contents.
ls -l ansible/group_vars/vault.yml
```

## Configure the administrator account

- Replace ansible/roles/linux_hardening/defaults/main.yml with:

```bash

---
# Dedicated account used for server administration.
linux_admin_user: linuxadmin
linux_admin_shell: /bin/bash

# The public key stays on the Ansible controller.
linux_admin_public_key_file: "{{ lookup('env', 'HOME') }}/.ssh/linux_hardening_ed25519.pub"

# Baseline SSH settings. We will enforce these after testing admin access.
ssh_port: 22
ssh_password_authentication: "no"
ssh_permit_root_login: "no"
ssh_pubkey_authentication: "yes"

# Firewall baseline. We will enable UFW only after confirming access.
ufw_default_incoming_policy: deny
ufw_default_outgoing_policy: allow
ufw_allowed_tcp_ports:
  - "{{ ssh_port }}"

# Maintenance and time synchronization settings.
security_updates_enabled: true
automatic_reboot_enabled: false
time_sync_service: chrony
```

- Now replace ansible/roles/linux_hardening/tasks/main.yml with the following initial setup stage.
- It creates the administrator and installs the key, but deliberately does not change SSH or enable the firewall yet.

```bash

---
# Stop early if this role is accidentally applied to an unsupported OS.
- name: Confirm that the target is Ubuntu with systemd
  ansible.builtin.assert:
    that:
      - ansible_distribution == "Ubuntu"
      - ansible_service_mgr == "systemd"
    fail_msg: >-
      This initial baseline expects Ubuntu with systemd.

# Validate the SSH port before using it in later firewall tasks.
- name: Confirm that the SSH port is valid
  ansible.builtin.assert:
    that:
      - ssh_port | int >= 1
      - ssh_port | int <= 65535
    fail_msg: "ssh_port must be a valid TCP port."

# Ensure the public key exists on the controller before changing the VM.
- name: Verify that the administrator public key exists
  ansible.builtin.stat:
    path: "{{ linux_admin_public_key_file }}"
  delegate_to: localhost
  become: false
  register: linux_admin_public_key_stat

- name: Require the administrator public key
  ansible.builtin.assert:
    that:
      - linux_admin_public_key_stat.stat.exists
      - linux_admin_public_key_stat.stat.isreg
    fail_msg: >-
      The administrator public key was not found on the Ansible controller.

# Refresh Ubuntu's package metadata before installing security tools.
- name: Update APT package metadata
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600

# Install the tools needed for the upcoming hardening stages.
- name: Install baseline security and time-sync packages
  ansible.builtin.apt:
    name:
      - chrony
      - ufw
      - unattended-upgrades
    state: present

# Create a dedicated administrator with a Vault-protected password hash.
- name: Create the Linux administration account
  ansible.builtin.user:
    name: "{{ linux_admin_user }}"
    shell: "{{ linux_admin_shell }}"
    create_home: true
    groups:
      - sudo
    append: true
    password: "{{ linux_admin_password_hash }}"
    update_password: on_create
    state: present

# Install only the public key; never copy the private key to the server.
- name: Install the administrator SSH public key
  ansible.posix.authorized_key:
    user: "{{ linux_admin_user }}"
    state: present
    key: "{{ lookup('file', linux_admin_public_key_file) }}"

# Ensure the time synchronization service is running.
- name: Enable and start Chrony
  ansible.builtin.service:
    name: chrony
    enabled: true
    state: started
```

## Load the variables and run the initial stage

- Update ansible/playbooks/harden.yml so it explicitly loads your project variables and encrypted Vault file:

```bash

---
- name: Apply the Linux server hardening baseline
  hosts: linux_servers
  become: true
  gather_facts: true

  # Load the project defaults and encrypted administrator password hash.
  vars_files:
    - ../group_vars/linux_servers.yml
    - ../group_vars/vault.yml

  roles:
    - linux_hardening
```

## Check and run the playbook

```bash
ansible-lint ansible/roles/linux_hardening/

# Validate the playbook structure without making changes.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --syntax-check \
  --vault-id @prompt

# Apply the initial account and package setup.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --vault-id @prompt

# Test SSH access using the new dedicated administrator key.
# This command checks the account identity and lists the sudo permissions available to linuxadmin.
ssh -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'whoami && sudo -n id'

# To connect to the VM
ssh \
  -i /home/pumej/projects/linux-server-hardening/vagrant/.vagrant/machines/Linux-hardening-vm/virtualbox/private_key \
  -p 2222 \
  -o IdentitiesOnly=yes \
  vagrant@127.0.0.1

#Set a password for linuxadmin user and try signing in again using the password.
sudo passwd linuxadmin
```

## Current validation results

```bash
Check                                                             Result
Ubuntu Server 22.04.5 LTS                                         Passed
Ansible hardening playbook                                        Passed — zero failures
Dedicated SSH key for linuxadmin                                  Passed
linuxadmin belongs to sudo group                                  Passed
Password-protected sudo                                           Passed — returned root
Original Vagrant administrative access                            Passed
```

## Add SSH hardening to the Ansible role

- Updaate file ansible/roles/linux_hardening/tasks/main.yml

```bash
# Apply SSH hardening in a dedicated configuration drop-in.
- name: Apply the SSH hardening configuration
  ansible.builtin.copy:
    dest: /etc/ssh/sshd_config.d/00-linux-hardening.conf
    owner: root
    group: root
    mode: "0644"

    # Render SSH settings from the shared Ansible variables.
    content: |
      Port {{ linux_hardening_ssh_port }}
      PermitRootLogin {{ linux_hardening_ssh_permit_root_login }}
      PasswordAuthentication {{ linux_hardening_ssh_password_authentication }}
      PubkeyAuthentication {{ linux_hardening_ssh_pubkey_authentication }}

    # Validate the candidate configuration before installing it.
    validate: "/usr/sbin/sshd -t -f %s"

  # Notify is a task-level directive, outside the copy parameters.
  notify: Reload SSH
```

## Add the SSH reload handler

- nano ansible/roles/linux_hardening/handlers/main.yml

```bash
---
# Reload SSH only when the configuration file changes.
- name: Reload SSH
  ansible.builtin.service:
    name: ssh
    state: reloaded
```

## Validate and apply again

```bash
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --syntax-check \
  --vault-id @prompt

# Check the role against Ansible Lint rules.
ansible-lint ansible/roles/linux_hardening/

# Apply the SSH hardening configuration to the Ubuntu VM.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --vault-id @prompt
```

## Verify the SSH setting for the VM

```bash
# Inspect the effective SSH settings using the administrator account.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'sudo sshd -T | grep -E "^(port|permitrootlogin|passwordauthentication|pubkeyauthentication) "'

- Expected output

port 22
permitrootlogin no
passwordauthentication no
pubkeyauthentication yes
```

## Next: verify fresh SSH key access

```bash
# Test a new SSH connection using the dedicated administrator key.
ssh -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'whoami'

- Expected output:

linuxadmin
```

## Confirm/check current firewall status

```bash
# Check whether UFW is currently active and review its existing rules.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'sudo ufw status verbose'
```

## What we'll do next

- Once key-based access is confirmed, we'll proceed in this order:

1. Configure UFW to allow SSH before enabling the firewall.
2. Apply the default-deny inbound and default-allow outbound policies.
3. Verify firewall status and SSH connectivity.
4. Configure and validate automatic security updates.
5. Run the full Ansible playbook again to confirm idempotency—that a second run makes no unnecessary changes.

- Important: We will not enable UFW until we've confirmed the SSH access path, so we reduce the risk of locking ourselves out of the VM.

## Add the SSH allow rule before enabling UFW

- Update ansible/roles/linux_hardening/tasks/main.yml file

```bash
# Set the default policy to deny unsolicited inbound connections.
- name: Set UFW default incoming policy
  community.general.ufw:
    direction: incoming
    policy: "{{ linux_hardening_ufw_default_incoming_policy }}"

# Permit outbound connections needed for updates and normal operations.
- name: Set UFW default outgoing policy
  community.general.ufw:
    direction: outgoing
    policy: "{{ linux_hardening_ufw_default_outgoing_policy }}"

# Explicitly allow SSH before activating the firewall.
- name: Allow SSH through UFW
  community.general.ufw:
    rule: allow
    port: "{{ linux_hardening_ssh_port | string }}"
    proto: tcp
```

- These tasks use the existing variables in ansible/group_vars/linux_servers.yml.
- The community.general.ufw module is provided by the community.general collection, so let's confirm that it is installed before running the playbook.

```bash
# Check whether the collection providing the UFW module is installed.
ansible-galaxy collection list community.general

# Install the collection used to manage UFW declaratively with Ansible.
ansible-galaxy collection install community.general
```

## Add the firewall activation task

- Update ansible/roles/linux_hardening/tasks/main.yml file

```bash
# Enable UFW only after the default policies and SSH allow rule are configured.
- name: Enable UFW firewall
  community.general.ufw:
    state: enabled
```

## Apply the hardening playbook again

```bash
# Apply the Linux hardening role, including the UFW configuration.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --vault-id @prompt
```

## Verify Firewall settinds again

```bash
# Check the active firewall status, default policies, and permitted SSH traffic.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'sudo ufw status verbose'

We want to confirm:
- Status: active
- Default incoming policy is deny
- Default outgoing policy is allow
- TCP port 22 is allowed for SSH

Expected output

Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere                  
22/tcp (v6)                ALLOW IN    Anywhere (v6)

- One note for later: the rule currently permits SSH from any IPv4 and IPv6 source. That's acceptable for this isolated local lab, 
- but for AWS and Azure deployments we'll restrict SSH at the cloud firewall level to your trusted public IP or CIDR.
```

## Configuring automatic security updates

- Inspect the current configuration of the VM

```bash
# Check whether unattended-upgrades is installed and enabled.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'dpkg-query -W -f="${Status}\n" unattended-upgrades; systemctl is-enabled unattended-upgrades 2>/dev/null || true'

- Then inspect the APT automatic-upgrade configuration:

# Display the active APT periodic-update settings.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || echo "No 20auto-upgrades file found"'
```

- Now let's make this configuration managed by Ansible, so it is repeatable across your Vagrant, AWS, and Azure deployments

## Create an Ansible template

- Create the template used to configure automatic APT updates and add below content.

```bash
nano ansible/roles/linux_hardening/templates/20auto-upgrades.j2

# Refresh APT package lists daily.
APT::Periodic::Update-Package-Lists "1";
# Install available unattended upgrades daily.
APT::Periodic::Unattended-Upgrade "1";

nano ansible/roles/linux_hardening/templates/52linux-hardening-unattended-upgrades.j2

{# Keep automatic reboots controlled by the shared Ansible variable. #}
Unattended-Upgrade::Automatic-Reboot "{{ linux_hardening_automatic_reboot_enabled | bool | lower }}";
```

## Add the automatic-update task to the hardening playbook

- nano ansible/roles/linux_hardening/tasks/main.yml

```bash
# Configure APT to check for and install unattended updates daily.
- name: Configure automatic APT updates
  ansible.builtin.template:
    src: 20auto-upgrades.j2
    dest: /etc/apt/apt.conf.d/20auto-upgrades
    owner: root
    group: root
    mode: "0644"
```

- This uses a template so Ansible owns the configuration rather than relying on whatever happened to be present on the VM

## Verify automatic-update configuration

```bash
# Verify the APT configuration managed by Ansible.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'cat /etc/apt/apt.conf.d/20auto-upgrades'

Expected settings:

APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";

- Verify package installation and reboot policy

# Confirm unattended-upgrades is installed and automatic reboots remain disabled.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'dpkg-query -W -f="${Status}\n" unattended-upgrades; grep -R "Automatic-Reboot" /etc/apt/apt.conf.d/ 2>/dev/null || true'

Outcome:

/etc/apt/apt.conf.d/50unattended-upgrades://Unattended-Upgrade::Automatic-Reboot "false";
/etc/apt/apt.conf.d/50unattended-upgrades:// when Unattended-Upgrade::Automatic-Reboot is set to true
/etc/apt/apt.conf.d/50unattended-upgrades://Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
/etc/apt/apt.conf.d/50unattended-upgrades://Unattended-Upgrade::Automatic-Reboot-Time "02:00";
```

- The APT configuration file is now managed by Ansible and has both daily update settings enabled.
- The automatic-reboot setting shown in your output is commented out, so it is not explicitly enabled in that file

## Update the hardening playbook

```bash
# Explicitly prevent unattended security updates from rebooting the server.
- name: Disable automatic reboots after unattended upgrades
  ansible.builtin.template:
    src: 52linux-hardening-unattended-upgrades.j2
    dest: /etc/apt/apt.conf.d/52linux-hardening-unattended-upgrades
    owner: root
    group: root
    mode: "0644"

- This aligns the server configuration with your existing variable
- linux_hardening_automatic_reboot_enabled: false. Later, we can make the template value conditional on that variable if you want the role to support different reboot policies.
```

- We've now implemented these core controls in your Linux hardening project:
- SSH key-based administration with root login disabled.
- UFW firewall with default-deny inbound traffic and SSH permitted.
- Daily APT package-list updates and unattended-upgrade scheduling.
- Explicitly disabled automatic reboots after unattended upgrades.

## Next: test idempotency

- A recruiter-ready Ansible project should be repeatable. If the server already matches the desired configuration, running the playbook again should ideally produce zero changes. Run the play book again

```bash
# Reapply the baseline to confirm that the configuration is repeatable.
ansible-playbook \
  -i ansible/inventories/vagrant/hosts.yml \
  ansible/playbooks/harden.yml \
  --vault-id @prompt

TASK [linux_hardening : Enable UFW firewall] *****************************************************************************************************************************************************************************
ok: [Linux-hardening-vm]

PLAY RECAP ***************************************************************************************************************************************************************************************************************
Linux-hardening-vm         : ok=18   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

Idempotency test passed
```

## Final Security verification

- We expect to confirm

- SSH root login disabled and password authentication disabled.
- UFW active, inbound default deny, outbound default allow, SSH permitted.
- Daily APT updates and unattended upgrades enabled.
- Automatic reboots explicitly disabled.
- unattended-upgrades installed.

```bash
# Verify SSH, firewall, automatic updates, and reboot policy in one session.
ssh -t \
  -i ~/.ssh/linux_hardening_ed25519 \
  -p 2222 \
  -o IdentitiesOnly=yes \
  linuxadmin@127.0.0.1 \
  'sudo sh -c '"'"'
    echo "=== SSH settings ==="
    sshd -T | grep -E "^(port|permitrootlogin|passwordauthentication|pubkeyauthentication) "
    echo
    echo "=== Firewall ==="
    ufw status verbose
    echo
    echo "=== Automatic update settings ==="
    cat /etc/apt/apt.conf.d/20auto-upgrades
    echo
    echo "=== Automatic reboot policy ==="
    cat /etc/apt/apt.conf.d/52linux-hardening-unattended-upgrades
    echo
    echo "=== Unattended-upgrades package ==="
    dpkg-query -W -f="${Status}\n" unattended-upgrades
  '"'"''

  - Expected outcome

  === SSH settings ===
port 22
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no

=== Firewall ===
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere                  
22/tcp (v6)                ALLOW IN    Anywhere (v6)             

=== Automatic update settings ===

# Refresh APT package lists daily.
APT::Periodic::Update-Package-Lists "1";

# Install available unattended upgrades daily.
APT::Periodic::Unattended-Upgrade "1";

=== Automatic reboot policy ===

# Explicitly prevent unattended upgrades from rebooting the server.
Unattended-Upgrade::Automatic-Reboot "false";

=== Unattended-upgrades package ==
```

```bash
# Encrypt the existing YAML file using a new or known Vault password.
ansible-vault encrypt ansible/group_vars/vault.yml

# Change the password used to encrypt/decrypt the existing Vault file.
ansible-vault rekey ansible/group_vars/vault.yml

# Test that the Vault file can be decrypted with the new password.
ansible-vault view ansible/group_vars/vault.yml
```

## Phase 2 — Make the project portable across environments

Phase 1: Local hardening baseline

Completed — Ansible tasks are idempotent, and the security validation playbook passes

## Choose a safe SSH access range

- The AWS security group should allow SSH only from your public IP using a /32 CIDR, rather than exposing port 22 to everyone.

```bash
# Display your current public IPv4 address.
curl -4 https://checkip.amazonaws.com
```

## We'll build a small, cost-conscious initial deployment with -

- One Ubuntu Linux EC2 instance.
- A dedicated VPC and public subnet.
- SSH access restricted to your public IP.
- An existing SSH public key, without uploading or committing the private key.
- Terraform variables and outputs, with state and local configuration files excluded from Git.

## Create the Terraform files for AWS provisioning

- versions.tf — Terraform and AWS provider

```bash
cat > aws/terraform/versions.tf <<'EOF'
terraform {
  # Require a modern Terraform version.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Use the region configured in terraform.tfvars.
provider "aws" {
  region = var.aws_region
}
EOF
```

- variables.tf — Reusable configuration

```bash
cat > aws/terraform/variables.tf <<'EOF'
variable "aws_region" {
  description = "AWS region where the Linux hardening lab will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used to identify resources belonging to this project."
  type        = string
  default     = "linux-hardening"
}

variable "instance_type" {
  description = "EC2 instance type. Check current pricing and eligibility before deployment."
  type        = string
  default     = "t3.micro"
}

variable "trusted_ssh_cidr" {
  description = "Trusted public IPv4 CIDR permitted to connect over SSH."
  type        = string

  # Require a narrowly scoped IPv4 CIDR instead of an unrestricted rule.
  validation {
    condition     = can(cidrnetmask(var.trusted_ssh_cidr)) && can(regex("/32$", var.trusted_ssh_cidr))
    error_message = "Use one trusted IPv4 address in /32 format, such as 203.0.113.10/32."
  }
}

variable "public_key_path" {
  description = "Path to the SSH public key on the machine running Terraform."
  type        = string
  default     = "~/.ssh/linux_hardening_ed25519.pub"
}
EOF
```

- main.tf — Network and Linux server

```bash
cat > aws/terraform/main.tf <<'EOF'
# Find a current Ubuntu 22.04 LTS x86_64 AMI published by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Select an available Availability Zone in the chosen region.
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a dedicated network for this lab.
resource "aws_vpc" "lab" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# Create a subnet for the Linux server.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

# Provide internet connectivity to the public subnet.
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# Route internet-bound traffic through the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

# Associate the public route table with the subnet.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Allow SSH only from the trusted public IPv4 address supplied in terraform.tfvars.
resource "aws_security_group" "linux" {
  name_prefix = "${var.project_name}-"
  description = "Restricted SSH access for the Linux hardening lab"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from the trusted administrator IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.trusted_ssh_cidr]
  }

  # Permit outbound traffic for package installation and system updates.
  egress {
    description = "Outbound IPv4 traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# Register the existing public key with AWS; never upload the private key.
resource "aws_key_pair" "admin" {
  key_name   = "${var.project_name}-admin"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Project = var.project_name
  }
}

# Deploy the Ubuntu server that Ansible will harden.
resource "aws_instance" "linux" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.linux.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = true

  # Require IMDSv2 to reduce risks from instance metadata exposure.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Use an encrypted general-purpose SSD for the operating system.
  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-ubuntu"
    Project = var.project_name
    Purpose = "Ansible Linux server hardening lab"
  }

  depends_on = [aws_route_table_association.public]
}
EOF
```

- outputs.tf — Useful deployment information

```bash
cat > aws/terraform/outputs.tf <<'EOF'
# Display the EC2 public IP for SSH and Ansible connectivity.
output "instance_public_ip" {
  description = "Public IPv4 address of the Ubuntu server."
  value       = aws_instance.linux.public_ip
}

# Display the private address used inside the VPC.
output "instance_private_ip" {
  description = "Private IPv4 address of the Ubuntu server."
  value       = aws_instance.linux.private_ip
}

# Display the instance ID for AWS CLI operations.
output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.linux.id
}

# Make the security boundary visible after deployment.
output "trusted_ssh_cidr" {
  description = "Public IPv4 CIDR permitted to connect over SSH."
  value       = var.trusted_ssh_cidr
}

# Show the command to connect using the local private key.
output "ssh_command" {
  description = "Example SSH command for the Ubuntu instance."
  value       = "ssh -i ~/.ssh/linux_hardening_ed25519 ubuntu@${aws_instance.linux.public_ip}"
}
EOF
```

- terraform.tfvars.example and your local settings. Create a safe template that can be committed, and a local terraform.tfvars file that should remain ignored by Git.

```bash
# Create a shareable example without your actual IP address.
cat > aws/terraform/terraform.tfvars.example <<'EOF'
aws_region       = "us-east-1"
project_name     = "linux-hardening"
instance_type    = "t3.micro"
trusted_ssh_cidr = "203.0.113.10/32" # Replace with your trusted public IPv4 /32.
public_key_path  = "~/.ssh/linux_hardening_ed25519.pub"
EOF

# Create your local configuration using the public IP checked earlier.
cat > aws/terraform/terraform.tfvars <<'EOF'
aws_region       = "us-east-1"
project_name     = "linux-hardening"
instance_type    = "t3.micro"
trusted_ssh_cidr = "104.9.152.207/32"
public_key_path  = "~/.ssh/linux_hardening_ed25519.pub"
EOF
```

## Validate the config files

```bash
# Confirm all five Terraform files exist.
ls -l aws/terraform/

# Format the Terraform configuration.
terraform -chdir=aws/terraform fmt -recursive

# Initialize the AWS provider.
terraform -chdir=aws/terraform init

# Check Terraform syntax and provider configuration.
terraform -chdir=aws/terraform validate

# Preview resources without creating them.
terraform -chdir=aws/terraform plan
```

## Create the automated AWS deployment script

- This script will coordinate Terraform and Ansible. It will reuse your existing playbooks and role, and it will stop if a prerequisite fails.

```bash
# Create a scripts directory for deployment automation.
mkdir -p scripts

# Create the AWS deployment orchestrator.
cat > scripts/deploy-aws.sh <<'EOF'
#!/usr/bin/env bash

# Stop on errors, unset variables, and failures inside pipelines.
set -Eeuo pipefail

# Resolve the project root so the script works from any directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/aws/terraform"
PUBLIC_KEY="${HOME}/.ssh/linux_hardening_ed25519.pub"
PRIVATE_KEY="${HOME}/.ssh/linux_hardening_ed25519"

# Temporary inventory is removed automatically when the script exits.
INVENTORY_FILE="$(mktemp)"
trap 'rm -f "${INVENTORY_FILE}"' EXIT

cd "${PROJECT_ROOT}"

echo "=== Preflight checks ==="

# Ensure Terraform, Ansible, AWS CLI, and SSH key files are available.
for command in terraform ansible-playbook aws ssh; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: ${command}" >&2
    exit 1
  fi
done

if [[ ! -f "${PUBLIC_KEY}" || ! -f "${PRIVATE_KEY}" ]]; then
  echo "ERROR: Expected SSH key pair was not found in ${HOME}/.ssh." >&2
  exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/ansible/group_vars/vault.yml" ]]; then
  echo "ERROR: Ansible Vault file is missing." >&2
  exit 1
fi

# Verify AWS credentials before attempting Terraform operations.
aws sts get-caller-identity >/dev/null

echo "Preflight checks passed."

echo "=== Terraform initialization and validation ==="

# Initialize the provider and validate the infrastructure configuration.
terraform -chdir="${TERRAFORM_DIR}" init
terraform -chdir="${TERRAFORM_DIR}" validate

echo "=== Review infrastructure plan ==="

# Show the proposed changes before creating AWS resources.
terraform -chdir="${TERRAFORM_DIR}" plan

echo
echo "Review the plan above. Terraform will ask for confirmation before creating resources."
read -r -p "Continue to Terraform apply? Type APPLY to proceed: " APPROVAL

if [[ "${APPROVAL}" != "APPLY" ]]; then
  echo "Deployment cancelled before infrastructure creation."
  exit 0
fi

# Terraform asks for its own confirmation unless -auto-approve is used.
terraform -chdir="${TERRAFORM_DIR}" apply

echo "=== Retrieve the EC2 address ==="

# Read the public IP from Terraform outputs after successful provisioning.
PUBLIC_IP="$(terraform -chdir="${TERRAFORM_DIR}" output -raw instance_public_ip)"

if [[ -z "${PUBLIC_IP}" ]]; then
  echo "ERROR: Terraform did not return an instance public IP." >&2
  exit 1
fi

echo "EC2 public IP: ${PUBLIC_IP}"

echo "=== Generate temporary Ansible inventory ==="

# Use Ubuntu's default cloud account for the initial connection.
# accept-new trusts a previously unknown host key on first connection.
# The inventory itself is temporary and is not committed to Git.
cat > "${INVENTORY_FILE}" <<INVENTORY
[linux_servers]
aws-linux ansible_host=${PUBLIC_IP} ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file=${PRIVATE_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
INVENTORY

echo "=== Wait for SSH connectivity ==="

# Wait until the newly created server is reachable over SSH.
ansible -i "${INVENTORY_FILE}" linux_servers \
  -m ansible.builtin.wait_for_connection \
  -a "timeout=600" \
  -o

echo "=== Apply Linux hardening ==="

# Prompt for the Ansible Vault password without putting it in the command line.
ansible-playbook \
  -i "${INVENTORY_FILE}" \
  ansible/playbooks/harden.yml \
  --ask-vault-pass

echo "=== Validate the hardening baseline ==="

# Run the existing read-only validation playbook.
ansible-playbook \
  -i "${INVENTORY_FILE}" \
  ansible/playbooks/validate.yml

echo
echo "Deployment and validation completed successfully."
echo "EC2 public IP: ${PUBLIC_IP}"
echo "SSH command: ssh -i ${PRIVATE_KEY} ubuntu@${PUBLIC_IP}"
echo
echo "The Ansible inventory was temporary and has been removed."
echo "Run the hardening playbook a second time to verify idempotency."
EOF

# Make the script executable.
chmod +x scripts/deploy-aws.sh
```

## How the automated run (script) works

1. Terraform initializes and validates the AWS configuration.
2. Terraform displays its plan, and you explicitly approve continuing.
3. Terraform asks for confirmation before provisioning.
4. The script retrieves the instance IP and creates a temporary Ansible inventory.
5. Ansible waits for SSH, prompts for your Vault password, applies hardening, and runs validation.
6. The temporary inventory is removed when the script exits.

- Security note: StrictHostKeyChecking=accept-new trusts a new SSH host key on first connection.
- This is convenient for a disposable lab, but it is trust-on-first-use rather than independent verification of the server's identity.
