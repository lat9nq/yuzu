#!/bin/bash
# deploy.sh [executable] [AppDir]
#   (Simplified) bash re-implementation of [linuxdeploy](https://github.com/linuxdeploy).
#   Reads [executable] and copies required libraries to [AppDir]/usr/lib
#   Copies the desktop and svg icon to [AppDir]
#   Respects the AppImage excludelist
#
# Unlike linuxdeploy, this does not:
# - Copy any icon other than svg (too lazy to add that without a test case)
# - Do any verification on the desktop file
# - Run any linuxdeploy plugins
# - *Probably other things I didn't know linuxdeploy can do*
#
# It notably also does not copy unneeded libraries, unlike linuxdeploy. On a desktop system, this
# can help reduce the end AppImage's size, although in a production system this script proved
# unhelpful.

_OBJDUMP_FLUFF="  NEEDED               "
_SEARCH_PATHS="$(echo -n "/usr/lib:/lib:${LD_LIBRARY_PATH}" | tr ':' ' ')"
_EXCLUDES=$(wget -qO - "https://raw.githubusercontent.com/AppImage/pkg2appimage/master/excludelist" | sed 's/#.*//' | xargs)

# find_library [library]
#   Finds the full path of partial name [library] in _SEARCH_PATHS
#   This is a time-consuming function.
function find_library {
    local _PATH=""
    for i in ${_SEARCH_PATHS}; do
        _PATH=$(find $i -regex ".*$1" -print -quit)
        if [ "$_PATH" != "" ]; then
            break
        fi
    done
    if [ -z $_PATH ]; then
        >&2 echo "WARNING: $1 failed to be located"
    else 
        echo -n $(readlink -e $_PATH)
    fi
}

# get_dep_names [object]
#   Returns a space-separated list of all required libraries needed by [object].
function get_dep_names {
    echo -n $(objdump -p $1 | grep NEEDED |  sed "s/${_OBJDUMP_FLUFF}//")
}

# get_deps [object] [library_path]
#   Finds and installs all libraries required by [object] to [library_path].
#   This is a recursive function that also depends on find_library.
function get_deps {
    local _DEST=$2
    local _EXCL=
    for i in $(get_dep_names $1); do
        _EXCL=`echo "$_EXCLUDES" | tr ' ' '\n' | grep $i`
        if [ "$_EXCL" != "" ]; then
            #>&2 echo "$i is on the exclude list... skipping"
            continue
        fi
        if [ -f $_DEST/$i ]; then
            continue
        fi
        
        local _LIB=$(find_library $i)
        if [ -z $_LIB ]; then
            continue
        fi
        cp -v $_LIB $_DEST/$i
        get_deps $_LIB $_DEST
    done
}

_ERROR=0
if [ -z $1 ]; then
    _ERROR=1
fi
if [ -z $2 ]; then
    _ERROR=1
fi

if [ $_ERROR -eq 1 ]; then
    >&2 echo "usage: $0 <file> <AppDir>"
    exit 1
fi

mkdir -p $2

cp -v $(readlink -e $(find $2 -type f -regex '.*\.desktop' -print -quit)) $2
cp -v $(readlink -e $(find $2 -type f -regex '.*\.svg' -print -quit)) $2

LIB_DIR=$2/usr/lib
mkdir -p $LIB_DIR
get_deps $1 $LIB_DIR

