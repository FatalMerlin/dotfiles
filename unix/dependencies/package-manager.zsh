ifpkg socat
ifpkg curl
ifpkg wget # needed for VS Code in WSL
ifpkg build-essential
ifpkg git
ifpkg git-lfs
ifpkg command-not-found
ifpkg bsdextrautils # column
ifpkg make

if ! (( IS_WSL )); then
    ifpkg binfmt-support # needed for WSL to be able to run Windows binaries
    ifpkg yakuake
    ifpkg xclip
fi