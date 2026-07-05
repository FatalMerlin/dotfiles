# allow re-sourcing after `installMissing`
unset missing
declare -A missing
unset _DPKG_STATUS
typeset -gA _DPKG_STATUS

function fal {
    alias | grep -- "$*"
}

# Adds the provided arguments to the .gitignore file if they are not already ignored by Git.
#
# Parameters:
#     - arg1, arg2, ...: The arguments to be added to the .gitignore file.
#
# Returns:
#     - 1 if no arguments are provided.
#     - 2 if not in a Git repository.
#     - None otherwise.
#
# Example usage:
#     $ gi file1 file2 directory1
function gi {
    fullpath=0
    if [ "$1" = "-f" ]; then
        fullpath=1
        shift
    fi
    if [ "$#" -eq 0 ]; then
        echo "No arguments provided"
        return 1
    fi
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$root" ]; then
        echo "Not in a Git repository"
        return 2
    fi

    modified=0
    gipath="$root/.gitignore"

    for arg in "$@"; do
        if [ ! -z $(git check-ignore --no-index "$arg") ]; then
            echo "Already ignored: $arg"
            continue
        fi
        if [ $fullpath -eq 1 ]; then
            if [[ $arg == */ ]]; then
                slash=1
            else
                slash=0
            fi
            arg="$(realpath "$arg" --relative-to "$root")"
            if [ $slash -eq 1 ]; then
                arg="$arg/"
            fi
        fi
        echo "$arg" >>"$gipath"
        if [ -z $(git check-ignore "$arg") ]; then
            echo "Already indexed: $arg"
        fi
        modified=1
    done

    if [ $modified -eq 1 ]; then
        sort "$gipath" -o "$gipath"
        git add "$gipath"
    fi
}

function gif {
    gi -f "$@"
}

function mkcd {
    mkdir -p "$@" && cd "$@"
}

# usage:
#   getInstallInstructions $cmd $source
# example:
#   getInstallInstructions ripgrep cargo
function getInstallInstructions {
    source="$1"
    package="$2"

    case "$source" in
    brew)
        installCmd="brew install $package"
        ;;
    cargo)
        installCmd="cargo install $package --locked"

        if [ -n "$(command -v sccache)" ]; then
            installCmd="RUSTC_WRAPPER=sccache $installCmd"
        fi
        ;;
    apt)
        installCmd="sudo apt-get update && sudo apt-get install -y $package"
        ;;
    custom)
        # the "package" is actually not the package name
        # but the install command
        installCmd="$package"
        ;;
    *)
        echo "echo 'unknown source: $source for package: $package'"
        ;;
    esac

    echo "$installCmd"
}

# checks if command exists and if not, adds it to the missing array
# usage:
#   ifcmd commandName commandSource commandPackageName
# example:
#   ifcmd sccache cargo sccache
function ifcmd {
    # Full path given (e.g. /home/linuxbrew/.linuxbrew/bin/brew): test executability directly.
    # Short name: use zsh commands hash — avoids forking a subshell for every check.
    if [[ "$1" == /* ]]; then
        [[ -x "$1" ]] || { missing["$1"]="$2:$3"; return 1; }
    else
        [[ -n "${commands[$1]}" ]] || { missing["$1"]="$2:$3"; return 1; }
    fi
}

function _ensure_dpkg_status() {
  (( ${#_DPKG_STATUS} > 0 )) && return
  local pkg pkg_status
  while IFS=$'\t' read -r pkg pkg_status; do
    _DPKG_STATUS[$pkg]="$pkg_status"
  done < <(dpkg-query -W -f='${Package}\t${Status}\n' 2>/dev/null)
}

function ifpkg {
    _ensure_dpkg_status
    if [[ "${_DPKG_STATUS[$1]}" != *"install ok"* ]]; then
        missing["$1"]="apt:$1"
        return 1
    fi
}

# defines an alias if the command exists
# usage:
#   ifalias aliasName aliasCmd cmdSrc [cmdPackageName] [cmdExecName]
# example:
#   ifalias ps procs cargo
#   ifalias z cargo zoxide zoxide
function ifalias {
    aliasName="$1"
    aliasCmd="$2"
    cmdSrc="$3"
    cmdPackageName="${4:-$aliasCmd}"
    # the name of the executable to check for
    # this covers the edge case of e.g. `zoxide`:
    #   - zoxide uses the `z` alias
    #   - `z` is not an executable, but a function
    #   - zoxide cannot be aliased directly
    cmdExecName="${5:-$aliasCmd}"

    if ifcmd "$cmdExecName" "$cmdSrc" "$cmdPackageName"; then
        if [ "$aliasName" != "$aliasCmd" ]; then
            alias "$aliasName"="$aliasCmd"
        fi
        return 0
    fi

    return 1
}

# reports missing commands
# has to be called after sourcing functions and aliases
# or after the last `ifalias` or `ifcmd` use
# but before the p10k instant prompt
function reportMissing {
    countMissing=${#missing[@]}

    if [ $countMissing -gt 0 ]; then
        echo "$countMissing missing packages detected"
	echo "> listMissing (lm)"
    fi
}

# lists missing commands
# stored in the `missing` associative array
# if called with any argument, no info for the installMissing
# command will be printed
function listMissing {
    if [ ${#missing[@]} -gt 0 ]; then
        echo "The following packages are missing from your system:"
        for cmd in "${(@k)missing}"; do
            echo "> $cmd"
        done

        if [ -n "$1" ]; then
            return
        fi

        echo
        echo "Run the following command to install them:"
	echo "> installMissing (im)"
    fi
}
alias lm=listMissing

# installs missing commands
function installMissing {
    if [ ${#missing[@]} -gt 0 ]; then
        listMissing noCmdInfo

        echo
        read -q "REPLY?Do you want to install the missing packages? [y/N]: "
        echo

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting."
            return;
        fi

        for cmd info in "${(@kv)missing}"; do
            cmdSrc=${info%%:*}
            cmdPackageName=${info#*:}

            installCmd=$(getInstallInstructions "$cmdSrc" "$cmdPackageName")
            echo "> $installCmd"

            # read -q "REPLY?Do you want to continue? [y/N]: "
            # echo
            # if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            #     continue
            # fi

            eval "$installCmd"
        done

        echo
        echo "Installation completed."
        echo "Reload the shell to see the changes:"
        echo "> source ~/.zshrc"
    fi
}
alias im=installMissing

function updateNeovim {
    install_path=${1:-"$HOME/Programs"}
    download_url=${2:-"https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"}
    link_path=${3:-"$HOME/.local/bin"}
    link_name=${4:-"nvim"}

    install_dir="$install_path/nvim"
    link_target="$link_path/$link_name"

    echo "install_path      =   $install_path"
    echo "download_url      =   $download_url"
    echo "link_path         =   $link_path"
    echo "link_name         =   $link_name"
    echo "install_dir       =   $install_dir"
    echo "link_target       =   $link_target"

    if [ -d "$install_dir" ]; then
        rm -r "$install_dir"
    fi

    #? In case the installation directory doesn't exist
    #? and wasn't deleted by the script
    if [ ! -d "$install_dir" ]; then
        mkdir -p "$install_dir"
    fi

    curl -#SL "$download_url" -o /tmp/nvim.tar.gz
    tar xzvf /tmp/nvim.tar.gz --strip 1 -C "$install_path"/nvim
    rm /tmp/nvim.tar.gz

    if ! [ -d "$link_path" ]; then
        mkdir -p "$link_path"
    elif [ -L "$link_target" ]; then
        rm "$link_target"
    fi

    ln -s "$install_path"/nvim/bin/nvim "$link_target"
}

function start_disowned {
    cmd="$1"
    shift
    "$cmd" "$@" &>/dev/null &! # ZSH built-in alias for `& disown`
}

function _ifpath {
    if [ $# -lt 1 ] || [ $# -gt 3 ]; then
        echo "[WARN] ifpath - wrong number of arguments: $#"
    fi

    check_path=$1
    # set_path=${2:-$1}
    concat_mode=${2:-"append"} # append, prepend

    if [ -d "$check_path" ]; then
        if [ $concat_mode = "prepend" ]; then
            export PATH="$check_path:$PATH"
        else
            export PATH="$PATH:$check_path"
        fi
    fi
}

function ifpath {
    _ifpath $@ "append"
}

function ifpath_append {
    _ifpath $@ "append"
}

function ifpath_prepend {
    _ifpath $@ "prepend"
}

function colorize {
  RED=`echo -e "\033[31m"`
  RESET=`echo -e "\033[0m"`

  while read line; do
    echo "${RED}${line}${RESET}"
  done < "${1:-/dev/stdin}"
}

function checkUpdates {
    "$HOME"/scripts/dependencies/update-check.sh
}

function installUpdates {
    "$HOME"/scripts/dependencies/update-install.sh
}

# from: https://github.com/charmbracelet/crush/issues/1415#issuecomment-3598309614
# Run command with 1Password secret refs (op://...) resolved via `op inject`
# 
# Translated from FISH to ZSH using ChatGPT:
# https://chatgpt.com/g/g-p-68eccc07e078819195b0e01958f13b40-linux/c/693ffedd-4f7c-832d-ad8f-5972eecd3e90
opx() {
  local -a template_lines resolved_lines
  local line name value

  # Scan exported env (like Fish's `set --names -x`)
  while IFS= read -r line; do
    name=${line%%=*}
    value=${line#*=}
    [[ $value == op://* ]] && template_lines+=("$name=$value")
  done < <(env)

  # If nothing to resolve, just run the command
  if (( ${#template_lines[@]} == 0 )); then
    [[ $# -gt 0 ]] && "$@"    # no-op if no args (matches Fish behavior)
    return
  fi

  # Resolve all refs in one `op inject` call
  local resolved
  if ! resolved=$(printf '%s\n' "${template_lines[@]}" | OP_ACCOUNT="$OP_ACCOUNT" op inject); then
    print -u2 -- "opx: failed to resolve secrets"
    print "%s\n" "$resolved"
    return 1
  fi
  resolved_lines=("${(@f)resolved}")  # split into array by newlines

  # Overlay resolved vars for the invoked command
  env "${resolved_lines[@]}" "$@"
}

function k8run {
    # set -x
    pod_name="tmp-shell-${RANDOM}"
    image_name="${1:-"debian"}"
    shift 2>/dev/null || true
    node_name="${1:-}"
    shift 2>/dev/null || true
    cmd=("$@")

    params=(
        $pod_name
        -ti
        --rm
        --restart=Never
        --image=$image_name
    )

    if [ -n "$node_name" ]; then
        node=$(kubectl get nodes -o name | grep -i "$node_name" | sed 's/^node\///' | head -n 1)
        if [ -z "$node" ]; then
            echo "Node $node_name not found"
            return 1
        fi
        params+=(--overrides="{\"spec\": { \"nodeSelector\": {\"kubernetes.io/hostname\": \"$node\"}}}")
    fi

    current_context=$(kubectl config current-context)
    current_namespace=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    
    echo "Running pod on context: $current_context, namespace: ${current_namespace:-default}"
    echo "Node: ${node:-"any"} - Image: $image_name - Cmd: ${cmd[*]}"
    {
        # set -x
        kubectl run "${params[@]}" -- "${cmd[@]}"
    }
}

function img_resize {
    local max_size="$1"
    local img_path="$2"
    local dir_name=$(dirname "$img_path")
    local base_name=$(basename "$img_path")
    local file_name="${base_name%.*}"
    local file_ext="${base_name##*.}"

    if [ ! -f "$img_path" ]; then
        echo "File not found: $img_path"
        return 1
    fi

    convert "$img_path" -resize "${max_size}x${max_size}>" "${dir_name}/${file_name}.${max_size}.${file_ext}"
}

function hgrep() { awk -v p="$1" 'NR==1 || $0 ~ p'; }