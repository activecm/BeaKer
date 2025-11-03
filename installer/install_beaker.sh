#!/bin/bash

BEAKER_VERSION="BEAKER_VERSION_REPLACE_ME"

if [ -n "$1" ]; then
	install_target="$1"
	shift
else
	echo "
Usage:
    $0 <target system(s)>

Examples:
    $0 127.0.0.1
    $0 10.1.1.1,10.2.2.2,10.3.3.3" >&2
	exit 1
fi

set -e

# change working directory to directory of this script
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
pushd "$SCRIPT_DIR" > /dev/null

source ./helper.sh

# Create a trap function to ensure that ssh-agent is stopped if it was started during installation.
trap_actions() {
	[ $started_ssh_agent ] && ssh-agent -k >/dev/null
}

trap trap_actions EXIT

targets_split=`echo "$install_target" | sed -e 's/,/\n/g' | sort -Vu`

# Fail if more than 1 target was specified and one of the targets is localhost
if [ $(echo "$targets_split" | wc -l) -gt 1 ] && $(echo "$targets_split" | grep -Eqi '^(.+@)?(127.0.0.1|localhost|::1)$'); then
    fail "Error while processing installation targets: host list contains multiple targets and includes localhost"
fi

# Parse out only remote targets
remote_targets=`echo "$targets_split" | grep -E -iv '^(.+@)?(127.0.0.1|localhost|::1)$' | sort -Vu`

# Only start ssh-agent if the user specifies remote targets
if [ -n "$remote_targets" ]; then
	status "Checking for ssh-agent..."
	
	if [ -z "$SSH_AUTH_SOCK" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
		status "Starting ssh-agent..."
		eval $(ssh-agent -s) >/dev/null
		started_ssh_agent=true
	fi
	
	status "Adding SSH keys to ssh-agent..."

	# Check ssh-add command output, store return code
	set +e
	ssh-add -q
	ssh_add_result=$?
	set -e

	# Per ssh-add manpage: If ssh-add returns 1, command failed. If 2, failed to connect to ssh-agent.
	# If a user is not using SSH keys, error code 1 may be nonfatal. However, error code 2 is likely fatal.
	if [ $ssh_add_result -eq 1 ]; then
		echo "$YELLOW"
		echo 'NOTE: Failed to add SSH keys to ssh-agent. There may be permission issues on ~/.ssh directory/files, or SSH keys may not be present. Continuing...'
		echo "$NORMAL"
	elif [ $ssh_add_result -eq 2 ]; then
		fail 'The ssh-add command was unable to connect to ssh-agent. Ensure that ssh-agent can be started by running "eval $(ssh-agent -s)"'
	fi
	
	status "Checking connectivity to remote targets..."
	
	unreachable=()
	for target in $remote_targets; do
		if ! ssh $target "true" 2>/dev/null; then
			unreachable+=($target)
		fi
	done
	
	# Fail (and print unreachable targets) if any remote targets were not reachable by SSH
	if [ ${#unreachable[@]} -ne 0 ]; then
		fail "The following target(s) were unreachable: ${unreachable[@]}"
	fi
fi

bash ./ansible-installer.sh

status "Installing BeaKer via Ansible on $install_target"

if [ "$install_target" = "localhost" -o "$install_target" = "127.0.0.1" -o "$install_target" = "::1" ]; then
	status "If asked for a 'BECOME password', that is your non-root sudo password on this machine."
	ANSIBLE_DISPLAY_SKIPPED_HOSTS=false ansible-playbook --connection=local -K -i "127.0.0.1," -e "install_hosts=127.0.0.1," install_pre.yml install_beaker.yml install_post.yml
else
	status "If asked for a 'BECOME password', that is your non-root sudo password on $install_target ."
	ANSIBLE_DISPLAY_SKIPPED_HOSTS=false ansible-playbook -K -i "${install_target}," -e "install_hosts=${install_target}," install_pre.yml install_beaker.yml install_post.yml
fi


echo "
        ______________
      <´-------------/
       |            |
       |            |
     __|   ______   |_______
    /  |  |BeaKer|  |      /
   /   |   ‾‾‾‾‾‾   |     /
  /    \____________/    /   ${BEAKER_VERSION}
 /                      /
/______________________/ 

Brought to you by Active CounterMeasures©
"
echo "BeaKer was successfully installed!"

# switch back to original working directory
popd > /dev/null