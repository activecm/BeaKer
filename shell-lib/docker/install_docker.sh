#!/bin/bash

# Change dir to script dir
pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" > /dev/null

# Bring in askYN, require_sudo, etc.
. ../acmlib.sh

# Options and Usage
# -----------------------------------
usage() {
	scriptName=$(basename "$0")
	echo -n "${scriptName} [OPTION]...
Install needed docker code to support AI Hunter.
Options:
  -g, --group-add       Add the current user to the 'docker' group
  -r, --replace-shell	(Implies -g) When finished, replaces the current shell
                        so the current user can control docker immediately.
                        This will prevent any calling scripts from executing further.
  -h, --help            Display this help and exit
"
}

ADD_DOCKER_GROUP=false

# Parse through command args to override values
while [[ $# -gt 0 ]]; do
	case $1 in
		-g|--group-add)
			ADD_DOCKER_GROUP=true
			;;
		-r|--replace-shell)
			ADD_DOCKER_GROUP=true
			REPLACE_SHELL=true
			;;
		-h|--help)
			usage >&2
			exit
			;;
		*)
			;;
	esac
	shift
done

# Check architecture to ensure 64 bit platform
if [ "$(arch)" != "x86_64" -a "$(arch)" != "aarch64" ]; then
	echo "Docker installation is only supported on 64-bit CPU architectures."
	exit 1
fi

require_sudo

# Store the exit code
./check_docker.sh
DOCKER_CHECK=$?
if [ "$DOCKER_CHECK" -gt 3 ]; then
	# This may overwrite a file maintained by a package.
	echo "An unsupported version of Docker appears to already be installed. It will be replaced."
fi
if [ "$DOCKER_CHECK" -eq 6 ]; then 
	echo "Docker is installed via snap, which is incompatible with ActiveCM software. Removing Docker via snap."
	$SUDO snap remove docker
fi
if [ "$DOCKER_CHECK" -eq 0 ]; then
	echo "Docker appears to already be installed. Skipping."
elif [ -s /etc/redhat-release ] && grep -iq 'release 7\|release 8\|release 9' /etc/redhat-release ; then
	#This configuration file is used in both Redhat RHEL and Centos distributions, so we're running under RHEL/Centos 7.x
	# https://docs.docker.com/engine/installation/linux/docker-ce/centos/

	# Removing podman and buildah packages
	if rpm -q podman >/dev/null 2>&1 || rpm -q buildah >/dev/null 2>&1; then
		echo -n "One or more of these packages are installed: podman, buildah. The docker installation may not work with these packages installed. Would you like to remove them? (recommended: yes)"
		if askYN ; then
			$SUDO yum -y -q -e 0 remove podman buildah
		else
			echo "You chose not to remove the podman and buildah packages. The install may not succeed."
		fi
	fi

    $SUDO yum -q -e 0 makecache fast > /dev/null 2>&1

	if rpm -q docker >/dev/null 2>&1 || rpm -q docker-common >/dev/null 2>&1 || rpm -q docker-selinux >/dev/null 2>&1 || rpm -q docker-engine >/dev/null 2>&1 ; then
		echo -n "One or more of these packages are installed: docker, docker-common, docker-selinux, and/or docker-engine. The docker website encourages us to remove these before installing docker-ce. Would you like to remove these older packages (recommended: yes)"
		if askYN ; then
			$SUDO yum -y -q -e 0 remove docker docker-common docker-selinux docker-engine
		else
			echo "You chose not to remove the older docker packages.  The install may not succeed."
		fi
	fi

	$SUDO yum -y -q -e 0 install yum-utils device-mapper-persistent-data lvm2 shadow-utils

	$SUDO yum-config-manager -q --enable extras >/dev/null

	if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
		$SUDO yum-config-manager -q --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null
	fi

	$SUDO wget -q https://download.docker.com/linux/centos/gpg -O ~/DOCKER-GPG-KEY
	$SUDO rpm --import ~/DOCKER-GPG-KEY

	$SUDO yum -y -q -e 0 install docker-ce
elif [ -s /etc/os-release ] && grep -iq '^ID *= *ubuntu' /etc/os-release ; then
	### Install Docker on Ubuntu ###
	# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-repository

	echo "Installing Docker package repo..."
	$SUDO apt-get -qq update > /dev/null 2>&1
	$SUDO apt-get install -qq \
		apt-transport-https \
		ca-certificates \
		curl \
		software-properties-common 

	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO apt-key add -

	if [ "$(uname -m)" = "x86_64" ]; then
		$SUDO add-apt-repository \
			"deb [arch=amd64] https://download.docker.com/linux/ubuntu \
			$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d '=' -f 2) \
			stable"
	elif [ "$(uname -m)" = "aarch64" ]; then
		$SUDO add-apt-repository \
			"deb [arch=arm64] https://download.docker.com/linux/ubuntu \
			$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d '=' -f 2) \
			stable"
	else
		echo "Unknown 64 bit architecture, exiting."
		exit 1
	fi

	echo "Installing latest Docker version..."
	$SUDO apt-get -qq update > /dev/null 2>&1
	$SUDO apt-get install -qq docker-ce
else
	echo "This system does not appear to be a Centos 7.x, RHEL 7.x, or Ubuntu Linux system.  Unable to install docker."
	exit 1
fi

# Start the Docker service:
echo "Starting the docker service..."
$SUDO systemctl start docker
$SUDO systemctl enable docker
echo "Docker service started."

./check_docker-compose.sh
# Store the exit code
DOCKER_COMPOSE_CHECK=$?
if [ "$DOCKER_COMPOSE_CHECK" -gt 3 ]; then
	# This may overwrite a file maintained by a package.
	echo "An unsupported version of Docker-Compose appears to already be installed. It will be replaced."
fi
if [ "$DOCKER_COMPOSE_CHECK" -eq 0 ]; then
	echo "Docker-Compose appears to already be installed. Skipping."
else
	### Install Docker-Compose ###
	# https://docs.docker.com/compose/install/linux/	

	echo "Installing Docker Compose..."

	# Uninstall docker-compose@v1 installed via pip
	PIP3_CMD="python3 -m pip"
	if [ -n "$SUDO" ]; then
		PIP3_CMD="$SUDO -H $PIP3_CMD"
	fi

	# Check if pip is callable
	if "$PIP3_CMD" --version > /dev/null 2>&1 ; then 
		# Check if docker-compose is installed via pip
		if [ "$PIP3_CMD" list | grep -s "docker-compose" ]; then
			# Attempt to uninstall docker-compose
			if [ "$PIP3_CMD" uninstall docker-compose ]; then
				echo "Uninstalled docker-compose@v1"
			fi
		fi
	fi

	# Update package lists again because docker adds the docker-compose-plugin repo
	# Install docker-compose-plugin
	if [ -s /etc/redhat-release ] && grep -iq 'release 7\|release 8' /etc/redhat-release ; then
		$SUDO yum -y -q update
		$SUDO yum -y -q -e 0 install docker-compose-plugin
	elif [ -s /etc/os-release ] && grep -iq '^ID *= *ubuntu' /etc/os-release ; then
		$SUDO apt-get -qq update > /dev/null 2>&1
		$SUDO apt-get -qq install docker-compose-plugin
	fi
	
	# Create alias for docker-compose to call docker compose
	echo 'docker compose "$@"' | $SUDO tee /usr/local/bin/docker-compose > /dev/null

	$SUDO chmod +x /usr/local/bin/docker-compose

	#Some OS don't insert /usr/local/bin into the PATH when running SUDO (CentOS)
	#Provide a symlink in /usr/bin in order to get around this issue.
	if [ ! -e /usr/bin/docker-compose ]; then 
    	$SUDO ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
	fi

	$SUDO mkdir -p "$HOME"/.docker
	$SUDO chown "$USER":"$USER" "$HOME"/.docker -R
	$SUDO chmod g+rwx "$HOME"/.docker -R
	
fi

if [ "${ADD_DOCKER_GROUP}" = "true" ]; then
	# Add current user to docker group
	echo "Adding current user to docker group..."
	#$SUDO groupadd docker
	$SUDO usermod -aG docker $USER

	if [ "${REPLACE_SHELL}" = "true" ]; then
		echo "Docker installation complete. You should have access to the 'docker' and 'docker compose' commands immediately."
		# Hack to activate the docker group on the current user without logging out.
		# Downside is it completely replaces the shell and prevents calling scripts from continuing.
		# https://superuser.com/a/853897
		exec sg docker newgrp `id -gn`
	fi

	echo "You will need to login again for these changes to take effect."
	echo "Docker installation complete. You should have access to the 'docker' and 'docker compose' commands once you log out and back in."
else
	echo "Docker installation complete. 'docker' and 'docker compose' must be run using sudo or the root account unless you have added your user to the 'docker' group."
fi

# Change back to original directory
popd > /dev/null
