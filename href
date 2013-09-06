#!/bin/bash

cur_off=0
per_page="${per_page:-250}"
unset pkglist

getpage() {
    tmplist=($(curl -sk "https://aur.archlinux.org/packages/?SB=n&SO=a&O=${cur_off}&PP=${per_page}" | xsltproc --html href.xslt -))
    last=$((${#tmplist[@]}-1))
    cur_page=${tmplist[$last-2]}
    max_page=${tmplist[$last]%*.}
    pkglist=("${tmplist[@]::$((last-6))}")
    echo -n "." >&2

    for pkg in "${pkglist[@]#/packages/*}"
    do
        printf "https://aur.archlinux.org/packages/%.2s/%s%s.tar.gz\n" $pkg $pkg ${pkg%/*}
    done

    if ((cur_page < max_page))
    then
        cur_off=$((per_page * cur_page))
        getpage
    fi
}

getpage