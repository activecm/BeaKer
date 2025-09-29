#!/bin/bash

# Copyright 2024, Active Countermeasures

pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" > /dev/null

source ./helper.sh

require_sudo() {
	# Stops the script if the user does not have root priviledges and cannot sudo
	# Additionally, sets $SUDO to "sudo" and $SUDO_E to "sudo -E" if needed.

	status "Checking sudo; if asked for a password this will be your user password on the machine running the installer."
	# If already running as root, do not run commands with sudo
	if [ "$EUID" -eq 0 ]; then
		SUDO=""
		SUDO_E=""
		return 0
	# If non-root user has sudo permissions, run commands with sudo
	elif sudo -v; then			#Confirms I'm allowed to run commands via sudo
		SUDO="sudo"
		SUDO_E="sudo -E"
		return 0
	# Otherwise, fail due to insufficient permissions
	else
		echo "It does not appear that user $USER has permission to run commands under sudo." >&2
		if grep -q '^wheel:' /etc/group ; then
			fail "Please run \`usermod -aG wheel $USER\` as root, log out, log back in, and retry the install"
		elif grep -q '^sudo:' /etc/group ; then
			fail "Please run \`usermod -aG sudo $USER\` as root, log out, log back in, and retry the install"
		else
			fail "Please give this user the ability to run commands as root under sudo, log out, log back in, and retry the install"
		fi
	fi
}


tmp_dir() {
	mkdir -p "$HOME/tmp/"
	tdirname=`mktemp -d -q "$HOME/tmp/install-tools.XXXXXXXX" </dev/null`
	if [ ! -d "$tdirname" ]; then
		fail "Unable to create temporary directory."
	fi
	echo "$tdirname"
}

enable_repositories() {
	status "Enable additional repository/repositories"

	if [ ! -s /etc/os-release ]; then
		fail "Unable to read /etc/os-release"
	else
		. /etc/os-release
		case "$ID/$VERSION_ID" in
		centos/9)
			$SUDO dnf config-manager --set-enabled crb
			$SUDO dnf install -y epel-release epel-next-release
			;;
		rhel/9*)
			$SUDO subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
			$SUDO dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
			;;
		ubuntu/*)
			$SUDO apt update
			$SUDO apt install -y software-properties-common || $SUDO apt install -y python-software-properties
			$SUDO add-apt-repository -y --update ppa:ansible/ansible
			;;
		*)
			fail "Unsupported OS $ID/$VERSION_ID"
			;;
		esac
	fi
}

patch_system() {
	# Update/upgrade system packages

	status "Patching system"
	if [ -x /usr/bin/apt-get -a -x /usr/bin/dpkg-query ]; then
		if [ -s /etc/os-release ] && egrep -iq '^ID=ubuntu' /etc/os-release ; then
			while ! $SUDO add-apt-repository -y universe ; do
				echo "Error subscribing to universe repository, perhaps because a system update is running; will wait 60 seconds and try again." >&2
				sleep 60
			done
		fi
		while ! $SUDO apt-get -q -y update >/dev/null ; do
			echo "Error updating package metadata, perhaps because a system update is running; will wait 60 seconds and try again." >&2
			sleep 60
		done
		while ! $SUDO apt-get -q -y upgrade >/dev/null ; do
			echo "Error updating packages, perhaps because a system update is running; will wait 60 seconds and try again." >&2
			sleep 60
		done
		while ! $SUDO apt-get -q -y install lsb-release >/dev/null ; do
			echo "Error installing lsb-release, perhaps because a system update is running; will wait 60 seconds and try again." >&2
			sleep 60
		done
	elif [ -x /usr/bin/yum -a -x /bin/rpm ]; then
		$SUDO yum -q -e 0 makecache
		$SUDO yum -q -e 0 -y update
		$SUDO yum -y -q -e 0 -y install yum-utils
		$SUDO yum -y -q -e 0 -y install redhat-lsb-core >/dev/null 2>/dev/null || /bin/true
		$SUDO yum -q -e 0 makecache
	fi
}


install_tool() {
	# Installs a program
	# $1: tool name
	# $2: list of packages that provide requested tool

	binary="$1"
	potential_packages="$2"

	if type -path "$binary" >/dev/null ; then
		status "== $binary executable is installed."
	else
		status "== Installing package that contains $binary"
		for one_package in $potential_packages ; do
			# Only attempt to install if not yet installed
			if ! type -path "$binary" >/dev/null ; then		#if a previous package was successfully able to install, don't try again.
				if [ -x /usr/bin/apt-get -a -x /usr/bin/dpkg-query ]; then
					$SUDO apt-get -q -y install $one_package
				elif [ -x /usr/bin/yum -a -x /bin/rpm ]; then
					$SUDO yum -y -q -e 0 install $one_package
				else
					fail "Neither (apt-get and dpkg-query) nor (yum, rpm, and yum-config-manager) is installed on the system"
				fi
			fi
		done
	fi

	if type -path "$binary" >/dev/null ; then
		return 0
	else
		echo "WARNING: Unable to install $binary from a system package" >&2
		return 1
	fi
}

require_sudo

status "Installing Ansible"

# check if macOS
if [ "$(uname)" == "Darwin" ]; then
	# check if ansible is installed
	which -s ansible
	if [[ $? != 0 ]] ; then
		# check if homebrew is installed
		which -s brew
		if [[ $? != 0 ]] ; then
			fail "Homebrew is required to install Ansible."
		fi
		# install ansible via homebrew
		echo "Installing Ansible via brew..."
		brew install ansible
	else 
		echo "== Ansible is already installed."
	fi
else
	patch_system

	enable_repositories

	status "Installing needed tools"
	install_tool python3 "python3"
	install_tool pip3 "python3-pip"
	python3 -m pip -V ; retcode="$?"
	if [ "$retcode" != 0 ]; then
		fail "Unable to run python3's pip, exiting."
	fi

	install_tool wget "wget"
	install_tool curl "curl"
	install_tool sha256sum "coreutils"
	install_tool ansible "ansible ansible-core"
fi

status "Preparing this system"
# Add /usr/local/bin/ to path if not present
if ! echo "$PATH" | grep -q '/usr/local/bin' ; then
	echo "Adding /usr/local/bin to path" >&2

	export PATH="$PATH:/usr/local/bin/"

	if [ -s /etc/environment ]; then
		echo 'export PATH="$PATH:/usr/local/bin/"' | $SUDO tee -a /etc/environment >/dev/null
	elif [ -s /etc/profile ]; then
		echo 'export PATH="$PATH:/usr/local/bin/"' | $SUDO tee -a /etc/profile >/dev/null
	else
		echo "Unable to add /usr/local/bin/ to path." >&2
	fi
fi

ansible-galaxy collection install community.docker --force

popd > /dev/null
