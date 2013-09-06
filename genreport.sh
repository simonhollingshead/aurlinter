#!/bin/bash

if [ ! -d ./res/exitedearly ]; then
	mkdir ./res/exitedearly
	bsdtar -C ./res/exitedearly -xzf ./res/exitedearly.tar.gz
fi

if [ ! -d ./res/aur ]; then
	mkdir ./res/aur
	bsdtar -C ./res/aur -xzf ./res/aur.tar.gz
	find ./res/aur/ -name "*.tar" | parallel -j8 'bsdtar -C ./res/aur -xf {}; rm {};' 
fi

if [ ! -f ./res/goodurls ]; then
	./urlcheck.sh
	./urlcheck.sh
	./urlcheck.sh -m
fi

printf "============================================[Resultant directory mess]\n"
cat ./res/dirmess
printf "\n\n"

printf "===================================================[Extraction errors]\n"
# These can't be reported in the loop for the following reasons:
# 1. If the extraction was to the root dir, I'd have nowhere to correctly log it.
# 2. If the archive contains two folders, where do I put this error to report in the right place?
cat ./res/extractbugs | grep -v " " | grep ":$" | sed 's/:$//'
printf "\n\n"

printf "====================================================[Terminated Early]\n"
# These aren't reported in the main loop since I don't know if they even HAVE a dir.
ls -1 ./res/exitedearly/ | cut -c 13-
printf "\n\n"

printf "=================================================[Main Package Faults]\n"
VALIDOPTIONS="strip\|docs\|libtool\|staticlibs\|emptydirs\|zipman\|purge\|upx\|debug\|ccache\|distcc\|buildflags\|makeflags"
find ./res/aur/* -maxdepth 1 -type d | parallel -k -j8 '
	cd {};
	DIR="{}"
	DIRNAME=${DIR##*/}
	ARCHIVEDIRNAME=$(cat archivedir_both)
	ERRORS=false
	ERRORMSG=""

	TEST=$(find . -maxdepth 1 -name "stderr_*" -exec tail -vn +1 \{\} \;)
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Outputs to stderr:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "stdout_*" -exec tail -vn +1 \{\} \;)
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Outputs to stdout:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "miscvars_*" -exec tail -vn +1 \{\} \;)
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Uses non _-prefixed variables:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "pkgdir_*" -exec tail -vn +1 \{\} \;)
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Sets pkgdir:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "startdir_*" -exec tail -vn +1 \{\} \;)
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Sets startdir:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "srcdir_*" -exec tail -vn +1 \{\} \;)
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Sets srcdir:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "pkgrel_*" -exec cat \{\} \;)
	{ [[ "$TEST" =~ [^0-9] ]] || [[ "$TEST" = "0" ]]; } && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Uses a non-integer or non-positive pkgrel. ($TEST)\n"

	TEST=$(find . -maxdepth 1 -name "epoch_*" -exec cat \{\} \;)
	[[ "$TEST" =~ [^0-9] ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Uses a non-integer or negative epoch. ($TEST)\n"

	TEST=$(find . -maxdepth 1 -name "arch_*" -exec cat \{\} \;)
	TEST=$(printf "%b" "$TEST" | grep -v "any\|i686\|x86_64\|arm\|armv6h\|armv7h")
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Unknown architectures in array:\n$TEST"

	! { echo "$DIRNAME" | grep "^$ARCHIVEDIRNAME$" >/dev/null; } && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Does not use directory name {} ($PKGNAME) as pkgname ($TEST).\n"

	TEST=$(find . -maxdepth 1 \( -name "source_*" -o -name "url_*" \) -exec cat \{\} \; -exec echo \;)
	TEST=$(printf "%b" "$TEST" | sed "s|/$||" | sed "s|^.*::||" | grep -Fhxf - ../../checkurls | sed "s/^.*:://")
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Uses URLs that appear to be unreachable:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "pkgbase_*" -print | wc -l)
	if [[ "$TEST" = "0" ]]; then
		TEST=$(grep -Fwif <(find . -maxdepth 1 -name "pkgname_*" -exec cat \{\} \; -exec echo \; | sed "/^$/d") <(find . -maxdepth 1 -name "pkgdesc_*" -exec cat \{\} \; | sed "/^$/d"))
	else
		TEST=$(grep -Fwif <(find . -maxdepth 1 -name "pkgbase_*" -exec cat \{\} \; -exec echo \; | sed "/^$/d") <(find . -maxdepth 1 -name "pkgdesc_*" -exec cat \{\} \; | sed "/^$/d"))
	fi
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Package name in pkgdesc:\n$TEST"

	TEST=$(find . -maxdepth 1 -name "options_*" -exec cat \{\} \; | sed "/^$/d" | sed "s/^!//" | grep  -xv "'$VALIDOPTIONS'")
	[[ "$TEST" != "" ]] && ERRORS=true && ERRORMSG="$ERRORMSG\n[*] Uses unknown options:\n$TEST"

	[[ "$ERRORMSG" != "" ]] && printf "%s:%b\n\n" "$ARCHIVEDIRNAME" "$ERRORMSG"
'

# echo; echo "=============[Depends on base/base-devel packages]"

# PKGPARAMS=(license groups depends optdepends makedepends checkdepends provides conflicts)
# filelist_data_check missing-crucial-field
# sources must contain all from noextract, install should NOT be in there.
# all files from archive must be in sources.