#!/bin/bash

#Copyright 2021, Active Countermeasures
#Author: William Stearns <bill@activecountermeasures.com>
#Based on steps provided by https://github.com/Sysinternals/SysmonForLinux/blob/main/INSTALL.md , which is under the MIT license

#Version 0.0.2


fail() {
	echo "$*, exiting." >&2
	exit 1
}


require_util () {
        #Returns true if all binaries listed as parameters exist somewhere in the path, False if one or more missing.
        while [ -n "$1" ]; do
                if ! type -path "$1" >/dev/null 2>/dev/null ; then
                        echo Missing utility "$1". Please install it. >&2
                        return 1        #False, app is not available.
                fi
                shift
        done
        return 0        #True, app is there.
} #End of requireutil


require_util lsb_release					|| fail 'Missing lsb_release'
require_util chown cut echo mv sudo wget			|| fail 'Missing a required utility'



distro=$(lsb_release -s -i)
version=$(lsb_release -s -r)

install_complete=''

case "$(echo "$distro" | tr A-Z a-z)" in
centos)
	case "$version" in
	7*|8*)
		require_util rpm yum				|| fail 'Missing a required utility'

		sudo rpm -Uvh 'https://packages.microsoft.com/config/centos/'"$(echo "$version" | cut -b 1)"'/packages-microsoft-prod.rpm'				#Will need to be updated if we get to centos >=10
		if sudo yum install sysmonforlinux ; then
			install_complete='true'
		fi
		;;
	*)
		fail "Unsupported $distro version"
		;;
	esac
	;;

debian)
	case "$version" in
	9|10|11)
		require_util apt-get gpg 			|| fail 'Missing a required utility'

		wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.asc.gpg
		sudo mv microsoft.asc.gpg /etc/apt/trusted.gpg.d/
		wget -q 'https://packages.microsoft.com/config/debian/'"$version"'/prod.list'
		sudo mv prod.list /etc/apt/sources.list.d/microsoft-prod.list
		sudo chown root:root /etc/apt/trusted.gpg.d/microsoft.asc.gpg
		sudo chown root:root /etc/apt/sources.list.d/microsoft-prod.list
		sudo apt-get update
		sudo apt-get install apt-transport-https
		sudo apt-get update
		if sudo apt-get install sysmonforlinux ; then
			install_complete='true'
		fi
		;;
	*)
		fail "Unsupported $distro version"
		;;
	esac
	;;

fedora)
	case "$version" in
	33|34)
		require_util dnf rpm				|| fail 'Missing a required utility'

		sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
		sudo wget -q -O /etc/yum.repos.d/microsoft-prod.repo 'https://packages.microsoft.com/config/fedora/'"$version"'/prod.repo'
		if sudo dnf install sysmonforlinux ; then
			install_complete='true'
		fi
		;;
	*)
		fail "Unsupported $distro version"
		;;
	esac
	;;

opensuse)
	case "$version" in
	15*)
		require_util rpm zypper 			|| fail 'Missing a required utility'

		sudo zypper install libicu
		sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
		wget -q 'https://packages.microsoft.com/config/opensuse/'"$(echo "$version" | cut -b 1-2)"'/prod.repo'
		sudo mv prod.repo /etc/zypp/repos.d/microsoft-prod.repo
		sudo chown root:root /etc/zypp/repos.d/microsoft-prod.repo
		if sudo zypper install sysmonforlinux ; then
			install_complete='true'
		fi
		;;
	*)
		fail "Unsupported $distro version"
		;;
	esac
	;;

rhel)
	case "$version" in
	7*|8*)
		require_util rpm yum 				|| fail 'Missing a required utility'

		sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
		sudo wget -q -O /etc/yum.repos.d/microsoft-prod.repo 'https://packages.microsoft.com/config/rhel/'"$(echo "$version" | cut -b 1)"'/prod.repo'		#Will need to be updated if we get to rhel >=10
		if sudo yum install sysmonforlinux ; then
			install_complete='true'
		fi
		;;
	*)
		fail "Unsupported $distro version"
		;;
	esac
	;;

sles)
	case "$version" in
	12*|15*)
		require_util rpm zypper				|| fail 'Missing a required utility'

		sudo rpm -Uvh 'https://packages.microsoft.com/config/sles/'"$(echo "$version" | cut -b 1-2)"'/packages-microsoft-prod.rpm'
		if sudo zypper install sysmonforlinux ; then
			install_complete='true'
		fi
		;;
	*)
		fail "Unsupported $distro version"
		;;
	esac
	;;

ubuntu)
	case "$version" in
	18.04|20.04|21.04)
		require_util apt-get dpkg			|| fail 'Missing a required utility'

		wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" -O packages-microsoft-prod.deb
		sudo dpkg -i packages-microsoft-prod.deb
		sudo apt-get update
		if sudo apt-get install sysmonforlinux ; then
			install_complete='true'
		fi
		;;
	*)
		fail "Unsupported $distro version"
		;;
	esac

	;;
*)
	fail "Unsupported distribution: $distro, please see https://github.com/Sysinternals/SysmonForLinux for install instructions"
	;;
esac


if [ "$install_complete" = "true" ]; then
	echo 'It appears that Sysmon for Linux was successfully installed.' >&2
else
	echo 'It does not appear that Sysmon for Linux was successfully installed.  Please check any error messages above and refer to https://github.com/Sysinternals/SysmonForLinux/blob/main/INSTALL.md and https://github.com/Sysinternals/SysmonForLinux/blob/main/README.md for more details' >&2
fi


