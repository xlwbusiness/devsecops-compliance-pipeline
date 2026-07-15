#!/bin/bash
# setup-devbox.sh - EC2 user-data bootstrap
#TODO: decide on error=handling flags and put here
set -euo pipefail
LOGFILE="/var/log/setup.log"
ERRORLOG="/var/log/setup.errors.log"

error_handler() {
	local exit_code=$?
	echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Command '${BASH_COMMAND}' failed on line ${BASH_LINENO[0]} with exit code ${exit_code}" | tee -a "$ERRORLOG" >&2
	exit "$exit_code"
	}
	
trap error_handler ERR

# --- Step 1: base system ---
# Update package, index, apply upgrades, install any base utilities I need (curl, unzip, git, ca-certificates...)
apt update && apt upgrade -y
apt install curl -y
curl --version
apt install unzip -y
unzip --version
apt install software-properties-common -y
add-apt-repository ppa:git-core/ppa -y
apt install git -y
git --version
apt install ca-certificates -y
dpkg -l | grep ca-certificates
apt install gnupg -y
gpg --version
apt update && apt install wget -y
wget --version
apt install apt-transport-https -y
apt update

# --- Step 2: host firewall ---
# Install ufw, set default deny/allow policy, enable it
# Think: Analyze the risk of enabling ufw in a script that runs unattended if I get the rules wrong.
# Also think about avoiding lockout given accessing this via SSM and not SSH
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
ufw status


# --- Step 3: Docker ---
# Install Docker officially using the official documentation
# Check: What group does a non-root user need to join to run docker commands without sudo
# Add Docker's official GPG key:
apt update
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt update

#Install the Docker packages
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
systemctl start docker
systemctl id-active --quiet docker
echo "Docker service is running"

# Allow non-root user to run commands using Docker
REAL_USER="ubuntu"
groupadd docker -f 
usermod -aG docker "$REAL_USER"
docker run hello-world
echo "Docker installed successfully. $REAL_USER can use Docker after logging out and back in."

#Since I ran sudo to start the script, we have to ensure that the new user group
# can run commands without root priveleges
if [[ -d "/home/$REAL_USER/.docker" ]]; then

	chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/.docker"
	chmod -R  g+rwx "/home/$REAL_USER/.docker"

fi

# --- Step 4: AWS CLI v2 ---
# Install the official AWS CLI and install so it can not be installed via apt
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
aws --version

# --- Step 5: Terraform ---
# Install the official repo for Terraform
# Follow HashiCorp's documented process for adding it securely

#Install HashiCorp's GPG key:
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

#Verify the GPG key's fingerprint:
gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint

#Add the official HashiCorp repository to the sytsem
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt update && apt install terraform -y
terraform plan -help

#Enable tab completion for Terraform
touch ~/.bashrc
su - "$REAL_USER" -c "terraform -install-autocomplete"

# ---Step 6: kubectl ---
# Installs the current stable version of Kubernetes.
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# --- Step 7: Helm ---
# Installs from official script on GitHub (the safe way)
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
helm version

# --- Step 8: Verify completion ---
echo "$(date '+%Y-%m-%d %H:%M:%S') - Setup completed successfully." | tee -a "$LOGFILE"
exit 0