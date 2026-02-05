# Active Countermeasures Script Library
# This library contains commonly used helper functions.

#### User Interface

askYN () {
    # Prints a question mark, reads repeatedly until the user
    # repsonds with t/T/y/Y or f/F/n/N.
    TESTYN=""
    while [ "$TESTYN" != 'Y' ] && [ "$TESTYN" != 'N' ] ; do
        echo -n '? ' >&2
        read -e TESTYN <&2 || :
        case $TESTYN in
        T*|t*|Y*|y*)		TESTYN='Y'	;;
        F*|f*|N*|n*)		TESTYN='N'	;;
        esac
    done

    if [ "$TESTYN" = 'Y' ]; then
        return 0 #True
    else
        return 1 #False
    fi
}

fail () {
    # Displays the passed in error and asks the user if they'd like to continue
    # the script. Will exit with error code 1 if the user stops the script.
    echo
    echo -e "\e[91mERROR\e[0m: $*" >&2
    echo "We recommend fixing the problem and restarting the install script. Would you like to continue anyway (Y) or stop the installation (N)?" >&2
    if askYN ; then
        echo "Script will continue at user request. This may not result in a working configuration." >&2
        sleep 5
    else
        exit 1
    fi
}

prompt2 () {
    # echo's the input to stderr, does not put a newline after the text
    echo -n "$*" >&2
}

echo2 () {
    # echo's the input to file descriptor 2 (stderr)
    echo "$*" >&2
}


status () {
    echo2 ""
    echo2 "================ $* ================"
    # DEBUG AID: Uncomment the lines below to enable pausing the install script
    # at each status marker
    #echo2 "Press enter to continue"
    #read -e JUNK <&2
}

#### Password Generation

generate_password() {
    # Allow custom password sizes, but default to 50
    SZ=${1:-50}
    if [ -x "$(command -v python2)" ]; then
        python2 -c "import os, string as s; print ''.join([(s.letters+s.digits+'_')[ord(i) % 63] for i in os.urandom($SZ)])"
    elif [ -x "$(command -v python3)" ]; then
        python3 -c "import os, string as s; print(''.join([(s.ascii_letters+s.digits+'_')[i % 63] for i in os.urandom($SZ)]))"
    elif [ -x "$(command -v dd)" ] && [ -x "$(command -v base32)" ]; then
        dd if=/dev/urandom bs=$SZ count=1 2>/dev/null | base32 --wrap=0
    elif [ -x "$(command -v perl)" ]; then
        # Perl's "rand" isn't cryptographically secure
        # http://sysadminsjourney.com/content/2009/09/16/random-password-generation-perl-one-liner/
        perl -le 'print map { (a..z,A..Z,0..9)[rand 62] } 0..pop' $SZ
    fi
}

#### Environment Variables

normalize_environment () {
    # Normalizes environment variables across different
    # environments.

    # Normalize the home directory. Sudo set's $HOME to /root
    # on CentOS 7
    if [ "$HOME" = "/root" -a -n "$SUDO_USER" -a "$SUDO_USER" != "root" ]; then
        export HOME="/home/$SUDO_USER/"
    fi
}

#### SSH Utilities

check_ssh_target_is_local () {
    # Returns whether a ssh target is set to a remote system
    [ -n "$1" ] && [[ "$1" =~ .*127.0.0.1$ ]]
}

check_ssh_target_is_remote () {
    # Returns whether a ssh target is set to a remote system
    [ -n "$1" ] && [[ ! "$1" =~ .*127.0.0.1$ ]]
}

can_ssh () {
    # Tests that we can reach a target system over ssh.
    # $1 must be the target, the following arguments are supplied to ssh
    if [ -z "$1" ]; then
        # Target is empty
        return 1
    fi

    echo2 "Verifying that we can ssh to $1 - you may need to provide a password to access this system."

    if ssh "$@" 'exit 0'; then
        # SSH successful
        return 0
    fi

    return 1
}

master_ssh() {
    #Creates a master ssh session/ socket which other connections
    #can piggyback off of. You must use the ssh flags returned by `get_master_ssh_flags`
    #in order to use the master socket.
    mkdir -p ~/.ssh/sockets/
    if ssh -o 'ControlPath=~/.ssh/sockets/master-%r@%h:%p' -O check "$@" >/dev/null 2>&1 ; then
    #If the master is currently running kill it so the socket is available for use.
        kill_master_ssh "$@"
    fi
    ssh -o 'ControlPath=~/.ssh/sockets/master-%r@%h:%p' -o 'ControlMaster=yes' -o 'ControlPersist=7200' -f "$@" 'sleep 7200'
}

kill_master_ssh () {
    #Kills a persistent ssh socket and all associated connections
    #Note that this kills not only the master but also any remaining client connections as well.
    ssh -o 'ControlPath=~/.ssh/sockets/master-%r@%h:%p' -O 'exit' "$@" >/dev/null 2>&1
}

get_master_ssh_flags () {
    #Returns the flags needed to piggyback a ssh connection off of a
    #master socket as created by `master_ssh`
    echo '-o ControlPath=~/.ssh/sockets/master-%r@%h:%p -o ControlMaster=no'
}

#### BASH Arrays

elementIn () {
    # Searches for the first argument in the rest of the arguments
    # array=("something to search for" "a string" "test2000")
    # containsElement "a string" "${array[@]}"
    local e match="$1"
    shift
    for e; do [[ "$e" = "$match" ]] && return 0; done
    return 1
}

caseInsensitiveElementIn () {
    # Searches for the first argument in the rest of the arguments
    # using a case insenstive comparison.
    local e match="${1,,}"
    shift
    for e; do [[ "${e,,}" = "$match" ]] && return 0; done
    return 1
}

#### System Tests

require_file () {
    #Stops the script if any of the files or directories listed do not exist.

    while [ -n "$1" ]; do
        if [ ! -e "$1" ]; then
            fail "Missing object $1. Please install it."
        fi
        shift
    done
    return 0							#True, all objects are here
}

require_sse4_2 () {
    #Stops the script is sse4_2 is not supported on the local system

    require_file /proc/cpuinfo  || fail "Missing /proc/cpuinfo - is this a Linux system?"
    if ! grep -q '^flags.*sse4_2' /proc/cpuinfo ; then
        fail 'This processor does not have SSE4.2 support needed for AI Hunter'
    fi
    return 0
}

require_free_space_MB() {
        # An array of directories consisting of all but the last function argument
    local dirs="${*%${!#}}"
        # The number of megabytes to check for is in the last function argument
    local mb="${@:$#}"

    # Check for free space:
    for one_dir in $dirs; do
        if [ $(df "$one_dir" -P -BM 2>/dev/null | grep -v 'Avail' | awk '{print $4}' | tr -dc '[0-9]') -ge $mb ]; then
            echo2 "$one_dir has at least ${mb}MB of free space, good."
        else
            fail "$one_dir has less than ${mb}MB of free space!"
        fi
    done

    return 0
}

warn_free_space_GB() {
    # Some directories will require a large amount of storage space, but only after
    # Zeek and AC-Hunter have been running for long enough to generate a good
    # amount of logs and databases. Thus, we only want to WARN the user at the end
    # without pausing the installer.

    # An array of directories consisting of all but the last function argument:
    local dirs="${*%${!#}}"
    # The number of gigabytes to check for is in the last function argument:
    local gb="${@:$#}"

    # Check for free space:
    for one_dir in $dirs; do
        if [ $(df "$one_dir" -P -BG 2>/dev/null | grep -v 'Avail' | awk '{print $4}' | tr -dc '[0-9]') -lt $gb ]; then
            # Print a warning. Use ANSI escape sequence [93m for bright yello, and [0m to reset:
            echo
            echo -e "\e[93mWARNING\e[0m: $one_dir does not have at least ${gb}GB of free space."
            echo "         AC-Hunter will still install successfully,"
            echo "         but you may need to frequently remove old data from $one_dir."
            echo "         Consider increasing the amount of space available in $one_dir."
            echo
        fi
    done

    return 0
}

warn_docker_network_in_use() {
    # Docker will claim networks if they're specified in a COMPOSE_FILE,
    # otherwise, Docker will claim a network from the pool defined in /etc/docker/daemon.json
    # Customers have been known to lose network connectivity to VPNs
    # if the VPN uses the claimed subnet. This function checks for and
    # warns the user if subnets could be claimed during installation.

    # If the user has configured the Docker daemon to use a non-default address pool,
    # disable the warning. The user has likely fixed any colliding network issues already.
    # To verify this would require JSON parsing and subnet calculations. Rather than
    # installing extra dependencies and performing extra checks, we hope for the best.
    if [ -f /etc/docker/daemon.json ] && grep -q "default-address-pools" /etc/docker/daemon.json; then
        return 0
    fi

    require_sudo

    # Set up local variables for arguments, ip routes, and grep matches
    local subnets="$@"
    local routes=`ip route`
    local matches=""
    if type docker > /dev/null 2>&1; then
        # Also check against docker networks
        local docker_networks=`for i in $($SUDO docker network ls -q); do $SUDO docker network inspect -f '{{if lt 0 (len .IPAM.Config)}}{{(index .IPAM.Config 0).Subnet}}{{end}}' $i; done`
    else
        local docker_networks=""
    fi
    #echo $docker_networks

    # Check if each argument is found in the ip route output. If so,
    # append to the string
    for net in $subnets; do
        if echo $routes | grep -q "$net" && ! echo $docker_networks | grep -q "$net"; then
            matches="${matches}             $net\n"
        fi
    done

    # Output warning if matches string is longer than 0 characters
    if [ ${#matches} -gt 0 ]; then
        echo
        echo -e "\e[93mWARNING\e[0m: This script checks for subnets in use which may be claimed"
        echo "         by the Docker configuration. The following subnet(s) were"
        echo "         found to be in use by the system:"
        echo -e "\n$matches"
        echo "         This script may disrupt network connectivity (such as VPN connections)."
        echo "         To prevent this, exit this script and edit the default address pool"
        echo "         used by Docker."
        echo
        echo "         For more information, please refer to our FAQ for more information:"
        echo "         https://portal.activecountermeasures.com/support/faq/?Display_FAQ=3350"
        echo
        echo "Press Enter to Continue..."
        read -e JUNK <&2
    fi

    return 0
}

check_os_is_centos () {
    [ -s /etc/redhat-release ] && grep -iq 'release 7\|release 8\|release 9' /etc/redhat-release
}

check_os_is_ubuntu () {
    grep -iq '^ID *= *ubuntu' /etc/os-release
}

require_supported_os () {
    #Stops the script if the OS is not supported

    #TODO: Test for minimum kernel version
    if check_os_is_centos ; then
        echo2 "CentOS or Redhat 7/8/9 installation detected, good."
    elif check_os_is_ubuntu ; then
        echo2 "Ubuntu installation detected, good."
    else
        fail "This system does not appear to be a CentOS/ RHEL 7/8/9 or Ubuntu system"
    fi
    return 0
}

require_util () {
    #Stops the script is any binary listed does not exist somewhere in the PATH.

    while [ -n "$1" ]; do
        if ! type -path "$1" >/dev/null 2>/dev/null ; then
            fail "Missing utility $1. Please install it."
        fi
        shift
    done
    return 0
}

require_sudo () {
    #Stops the script if the user does not have root priviledges and cannot sudo
    #Additionally, sets $SUDO to "sudo" and $SUDO_E to "sudo -E" if needed.

    if [ "$EUID" -eq 0 ]; then
        SUDO=""
        SUDO_E=""
        return 0
    fi

    if sudo -v; then
        SUDO="sudo"
        SUDO_E="sudo -E"
        return 0
    fi
    fail 'Missing administrator priviledges. Please run with an account with sudo privilidges.'
}

require_selinux_permissive () {
    # If SELinux is installed and in enforcing mode, fail and notify the user to set it to permissive.
    if [ -n "`type -path sestatus`" ] && [ "`sestatus | grep -E -i '(^Current mode|^SELinux status)' | awk '{print $3}' | grep -i 'enforcing'`" = "enforcing" ]; then
        fail "`hostname` is running SELinux in enforcing mode. Please run 'setenforce permissive' on all systems and restart the installer."
    fi
}

require_executable_tmp_dir () {
    NEWTMP="$HOME/.tmp"
    if [ -n "$TMPDIR" ] && findmnt -n -o options -T "$TMPDIR" | grep -qvE '(^|,)noexec($|,)' ; then
        : # we have an executable tmpdir. Good.
    elif [ -d "/tmp" ] && findmnt -n -o options -T "/tmp" | grep -qvE '(^|,)noexec($|,)' ; then
        export TMPDIR="/tmp"
    else
        mkdir -p "$NEWTMP"
        if findmnt -n -o options -T "$NEWTMP" | grep -qE '(^|,)noexec($|,)' ; then
            fail 'Could not create a temporary directory in an executable volume. Set your TMPDIR environment variable to a directory on an executable volume and retry.'
        fi
        export TMPDIR="$(realpath "$NEWTMP")"
    fi
    return 0
}


can_write_or_create () {
    # Checks if the current user has permission to write to the provided file or directory.
    # If it doesn't exist then it recursively checks if the file and all parent directories
    # can be created.

    local file="$1"

    if [ ! -e "$file" ]; then
        # if the file doesn't exist then return whether or not we can write to the parent directory
        can_write_or_create "$(dirname "$file")"
    elif [ -w "$file" ]; then
        # if the file exists and is writable return true
        true
    else
        # otherwise we know the file doesn't exist and is not writable with the current user
        false
    fi
}

ensure_common_tools_installed () {
    #Installs common tools used by acm scripts. Supports yum and apt-get.
    #Stops the script if neither apt-get nor yum exist.

    require_sudo

    local ubuntu_tools="gdb wget curl iproute2 make netcat-openbsd openssh-client rsync unzip tar tzdata"
    local centos_tools="gdb wget curl make nmap-ncat coreutils iproute openssh-clients rsync unzip tar tzdata"
    local required_tools="adduser awk cat chmod chown cp curl date egrep gdb getent grep ip make mkdir mv nc passwd printf rm rsync sed ssh-keygen sleep tar tee tr unzip wc wget"
    if [ -x /usr/bin/apt-get -a -x /usr/bin/dpkg-query ]; then
        #We have apt-get, good.

        if ! type -f realpath >/dev/null 2>&1 ; then
            #If realpath isn't installed, we need to install it.
            #Check Ubuntu version

            # Source os-release to avoid using lsb_release.
            # Relevant variable is $VERSION_CODENAME.
            . /etc/os-release
            if [ "$VERSION_CODENAME" = "xenial" ]; then
                #Adjust package list for 16.04
                ubuntu_tools="$ubuntu_tools realpath"
            else
                #Adjust package list for 18.04 and above
                ubuntu_tools="$ubuntu_tools coreutils"
                if [ "$VERSION_CODENAME" = "focal" ]; then				#Ubuntu 20.04 LTS needs a key imported for the install to work.
                    $SUDO apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 656408E390CFB1F5
                fi
            fi
        fi
        
        

        #We're returning to showing stderr because using "-qq" and redirecting stderr to /dev/null meant the user could never see why an install was failing.
        while ! $SUDO apt-get -q -y update >/dev/null ; do
            echo2 "Error updating package metadata, perhaps because a system update is running; will wait 60 seconds and try again."
            sleep 60
        done

        if [ -z "$SUDO" ]; then # split out the case for when sudo is not set in order to avoid command parsing issues
            # set env variables to install without prompts (e.g. tzdata)
            local old_deb_frontend="$DEBIAN_FRONTEND"
            export DEBIAN_FRONTEND=noninteractive

            while ! apt-get -q -y install $ubuntu_tools >/dev/null ; do
                echo2 "Error installing packages, perhaps because a system update is running; will wait 60 seconds and try again."
                sleep 60
            done

            export DEBIAN_FRONTEND="$old_deb_frontend"
        else
            while ! $SUDO DEBIAN_FRONTEND=noninteractive apt-get -q -y install $ubuntu_tools >/dev/null; do
                echo2 "Error installing packages, perhaps because a system update is running; will wait 60 seconds and try again."
                sleep 60
            done
        fi      

    elif [ -x /usr/bin/yum -a -x /bin/rpm ]; then
        #We have yum, good.

        #Make sure we have yum-config-manager. It might be in yum-utils.
        if [ ! -x /bin/yum-config-manager ]; then
            $SUDO yum -y -q -e 0 install yum-utils
        fi

        #Addresses AC-Hunter issue #2185
        if [ -x /usr/bin/subscription-manager ]; then		#Only attempt this on RHEL, not Centos or other clones
            #Note, when extending to other RHEL releases (>7.x) we'll need to test for the release version and adjust the repository name.
            $SUDO subscription-manager repos --enable=rhel-7-server-extras-rpms
        fi

        $SUDO yum -q -e 0 makecache > /dev/null 2>&1
        #Yum takes care of the lock loop for us
        #--skip-broken prevents any attempts to install uninstallable packages (the user may have conflicting packages installed)
        $SUDO yum -y -q -e 0 --skip-broken install $centos_tools
    else
        fail "Neither (apt-get and dpkg-query) nor (yum, rpm, and yum-config-manager) is installed on the system"
    fi

    require_util $required_tools

    # handle tzdata which does not install an executable on the system
    if [ ! -e "/etc/localtime" ]; then  # use -e to cover both symlinks and regular files
        fail "Missing utility tzdata. Please install it."
    fi

    return 0
}

move_working_directory () {
    # Moves the working directory to another path given by $1.
    # If the running directory is /home/user/AIH-latest, then
    # calling move_working_directory '/opt' will result in a working
    # directory of /opt/AIH-latest.
    # If the current user does not have sufficient permissions to move
    # the working directory to the target directory, the files are moved
    # using sudo and root is given ownership of the resulting files.

    local current_directory=`pwd -P`
    local target_directory="$1/$(basename "$current_directory")"

    local move_dir_sudo=""
    if ! can_write_or_create "$1"; then
        require_sudo
        $SUDO mkdir -p "$1"
        $SUDO mv "$current_directory" "$1"
        $SUDO chown -R root:root "$target_directory"
    else
        mkdir -p "$1"
        mv "$current_directory" "$1"
    fi

    cd "$target_directory"
    return 0
}
