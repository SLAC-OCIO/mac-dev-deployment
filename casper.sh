#!/usr/bin/env bash

BGreen='\e[1;32m'       # Green
BRed='\e[1;31m'         # Red
Color_Off='\e[0m'       # Text Reset
BASEDIR=`dirname $0`
WORKINGDIR=~/.slac-mac
ROLESDIR=~/roles
localuser=$3

function setStatusMessage {
    printf "${IRed} --> ${BGreen}$1${Color_Off}\n" 1>&2
}

printf "${BRed}    _____ _               _____      ____   _____ _____ ____  ${Color_Off}\n"
printf "${BRed}   / ____| |        /\   / ____|    / __ \ / ____|_   _/ __ \ ${Color_Off}\n"
printf "${BRed}  | (___ | |       /  \ | |        | |  | | |      | || |  | |${Color_Off}\n"
printf "${BRed}   \___ \| |      / /\ \| |        | |  | | |      | || |  | |${Color_Off}\n"
printf "${BRed}   ____) | |____ / ____ \ |____    | |__| | |____ _| || |__| |${Color_Off}\n"
printf "${BRed}  |_____/|______/_/    \_\_____|    \____/ \_____|_____\____/ ${Color_Off}\n\n"

setStatusMessage "Checking if we need to ask for a sudo password"

sudo -v
export ANSIBLE_ASK_SUDO_PASS=True

username=all
if [ ! -z "$4" ]; then
    profile=$4
fi

if [[ ! -d $WORKINGDIR ]]; then
    mkdir -p ~/.slac-mac/
fi

function triggerError {
    printf "${BRed} --> $1 ${Color_Off}\n" 1>&2
    exit 1
}

# Check whether a command exists - returns 0 if it does, 1 if it does not
function exists {
  if command -v $1 >/dev/null 2>&1
  then
    return 0
  else
    return 1
  fi
}

# credits https://github.com/boxcutter/osx/blob/master/script/xcode-cli-tools.sh
function install_clt {
    # Get and install Xcode CLI tools
    OSX_VERS=$(sw_vers -productVersion | awk -F "." '{print $2}')

    # on 10.9+, we can leverage SUS to get the latest CLI tools
    if [ "$OSX_VERS" -ge 9 ]; then
        # create the placeholder file that's checked by CLI updates' .dist code
        # in Apple's SUS catalog
        touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        # find the CLI Tools update
        PROD=$(softwareupdate -l | grep "\*.*Command Line" | head -n 1 | awk -F"*" '{print $2}' | sed -e 's/^ *//' | tr -d '\n')
        # install it
        softwareupdate -i "$PROD" -v
        rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    # on 10.7/10.8, we instead download from public download URLs, which can be found in
    # the dvtdownloadableindex:
    # https://devimages.apple.com.edgekey.net/downloads/xcode/simulators/index-3905972D-B609-49CE-8D06-51ADC78E07BC.dvtdownloadableindex
    else
        [ "$OSX_VERS" -eq 7 ] && DMGURL=http://devimages.apple.com.edgekey.net/downloads/xcode/command_line_tools_for_xcode_os_x_lion_april_2013.dmg
        [ "$OSX_VERS" -eq 7 ] && ALLOW_UNTRUSTED=-allowUntrusted
        [ "$OSX_VERS" -eq 8 ] && DMGURL=http://devimages.apple.com.edgekey.net/downloads/xcode/command_line_tools_for_osx_mountain_lion_april_2014.dmg

        TOOLS=clitools.dmg
        curl "$DMGURL" -o "$TOOLS"
        TMPMOUNT=`/usr/bin/mktemp -d /tmp/clitools.XXXX`
        hdiutil attach "$TOOLS" -mountpoint "$TMPMOUNT"
        installer $ALLOW_UNTRUSTED -pkg "$(find $TMPMOUNT -name '*.mpkg')" -target /
        hdiutil detach "$TMPMOUNT"
        rm -rf "$TMPMOUNT"
        rm "$TOOLS"
        exit
    fi
}

setStatusMessage "Keep-alive: update existing sudo time stamp until we are finished"

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

export HOMEBREW_CASK_OPTS="--appdir=/Applications"

if [[ ! -f "/Library/Developer/CommandLineTools/usr/bin/clang" ]]; then
    setStatusMessage "Install the CLT"
    install_clt
fi

# Install Ansible
if ! exists pip; then
    setStatusMessage "Install PIP"
    sudo easy_install --quiet pip
fi
if ! exists ansible; then
    setStatusMessage "Install Ansible"
    sudo pip install -q ansible
fi

sudo /usr/local/bin/pip install gitpython
sudo /usr/local/bin/pip install pygithub

setStatusMessage "Get SLAC configs"
#Get the required configs
	echo "Getting the correct configs/n"
	mkdir -p ~/.slac-mac
	git clone -q https://github.com/SLAC-ocio/mac-dev-deployment ~/.slac-mac/


setStatusMessage "Create necessary folders"

sudo mkdir -p /usr/local/grail
sudo mkdir -p /usr/local/grail/roles
sudo chmod -R g+rwx /usr/local
sudo chgrp -R admin /usr/local

if [ -d "/usr/local/grail/config" ]; then
    setStatusMessage "Update your config from git"
    cd /usr/local/grail/config
    git pull -q
else
        setStatusMessage "Getting your config from your fork"
        git clone -q https://github.com/slac-ocio/grail-config.git /usr/local/grail/config
fi

cd /usr/local/grail

setStatusMessage "Create ansible.cfg"

{ echo '[defaults]'; echo 'roles_path=/usr/local/grail/roles:/usr/local/grail/config/roles'; } > ansible.cfg

setStatusMessage "Get all the required roles"

ansible-galaxy install -f -r config/requirements.yml -p roles

if [ -f "config/$profile.yml" ]; then
    setStatusMessage "Running the ansible playbook for $profile"
    ansible-playbook -i "localhost," config/$profile.yml -e user=$localuser
else
    if [ "travis" = "$profile" ]; then
        setStatusMessage "Running the ansible playbook for $profile but use admin.yml as fallback"
        ansible-playbook -i "localhost," config/admin.yml
    else
        triggerError "No playbook for $profile found"
    fi
fi

