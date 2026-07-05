#!/usr/bin/env bash
# Based on https://stuartleeks.com/posts/wsl-ssh-key-forward-to-windows/ with fixes & improvements

# Load / run this file during startup of your shell, e.g. in your `.zshrc` or `.bashrc`
# You can use this snippet to only run it in WSL:
# 
# # only run in WSL
# if [[ $(grep -i Microsoft /proc/version) ]]; then
#   export IS_WSL=1
#   $HOME/.agent-bridge.sh
# else
#   export IS_WSL=0
# fi

set -uo pipefail

if ! command -v socat >/dev/null 2>&1; then
    echo "socat is required for ssh forwarding but not found in PATH. Please install it and try again."
    echo "On Debian/Ubuntu, you can install it with:"
    echo "> sudo apt install socat"
    exit 1
fi

if ! command -v npiperelay.exe >/dev/null 2>&1; then
    echo "npiperelay.exe is required for ssh forwarding but not found in PATH. Please install it and try again."
    echo "You can install it with winget on Windows:"
    echo "> winget install -e --id jstarks.npiperelay"
    exit 1
fi

if ! [ -d "$HOME/.1password" ]; then
    mkdir -p "$HOME/.1password"
fi

# Configure ssh forwarding
export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
# need `ps -ww` to get non-truncated command for matching
# use square brackets to generate a regex match for the process we want but that doesn't match the grep command running it!
#! doesn't work reliably, e.g. if ssh-agent is running but not working, it will still report as running and skip the fixup
#ALREADY_RUNNING=$(ps -auxww | grep -q "[n]piperelay.exe -ei -s //./pipe/openssh-ssh-agent"; echo $?)
ALREADY_RUNNING=$(
    ssh-add -l 2>&1 >/dev/null
    echo $?
)
if [[ $ALREADY_RUNNING != "0" ]]; then
    if [[ -S $SSH_AUTH_SOCK ]]; then
        echo "Killing dangling socat..."
        ps -auxww | grep "[n]piperelay.exe -ei -s //./pipe/openssh-ssh-agent" | awk '{ print $2 }' | xargs --no-run-if-empty kill -9
        # not expecting the socket to exist as the forwarding command isn't running (http://www.tldp.org/LDP/abs/html/fto.html)
        if [[ -S $SSH_AUTH_SOCK ]]; then
            echo "Removing previous socket..."
            rm "$SSH_AUTH_SOCK"
        fi
    fi
    echo "Starting SSH-Agent relay..."
    # setsid to force new session to keep running
    # set socat to listen on $SSH_AUTH_SOCK and forward to npiperelay which then forwards to openssh-ssh-agent on windows
    (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
else
    echo "ssh-agent OK"
fi

set +uo pipefail
