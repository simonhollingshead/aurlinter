#!/bin/bash

# If this runs on my real system, bad things will happen.
[[ $(hostname) = "aur-sandbox" ]] || exit 1

VMHOSTPATH=/home/aur/sf_aur-things
RESULTPATH="$VMHOSTPATH"/res
VMGUESTPATH=/home/aur

cleanup() {
	rm -rf "$VMGUESTPATH"/{pkgs,extracted}/ "$VMGUESTPATH"/tmp/ "$VMGUESTPATH"/urls
	mkdir -p "$VMGUESTPATH"/{pkgs,extracted}/ "$VMGUESTPATH"/tmp/aur/
}

genpkgs() {
	cd "$VMHOSTPATH"
	./href.sh > "$VMGUESTPATH"/urls
	aria2c -d "$VMGUESTPATH"/pkgs -c -i "$VMGUESTPATH"/urls
}

extractpkgs() {
	# First piece of actual testing.  For each downloaded archive, extract.
	# If A.tar.gz doesn't extract only contain a folder called A then report it.
	# bsdtar is far better with some of the oddball compression tools the maintainers have used.
	cd "$VMGUESTPATH"
	for i in pkgs/*.tar.gz
	do
		printf "%s\n" "$i"
	done | parallel -j8 -k '
	TMP={}          # pkgs/A.tar.gz
	TMP=${TMP#*/}   # A.tar.gz
	TMP=${TMP%.*.*} # A
	OUT=$(bsdtar -C extracted -xvf "{}" 2>&1)
	OUTBADNAME=$(printf "%b" "$OUT" | grep -iv "^x $TMP$\|^x $TMP/\|^bsdtar:")
	OUTERR=$(printf "%b" "$OUT" | grep -i ":\|^bsdtar:")
	if [[ "$OUTBADNAME""$OUTDOTFILE""$OUTERR" != "" ]]; then
		printf "%s:\n" "$TMP"
		[[ "$OUTBADNAME" != "" ]] && printf "Incorrect directory names:\n%b\n\n" "$OUTBADNAME"
		[[ "$OUTERR" != "" ]] && printf "Decompression errors generated:\n%b\n\n" "$OUTERR"
		printf "\n"
	fi
	' > "$RESULTPATH"/extractbugs
}

analyseall() {
	# TODO: I know all this tmp stuff is sloppy.  I started off using /tmp/, but it wasn't big enough.
	cd "$VMGUESTPATH"

	# Anybody with an archive where there is no package named directory (depth 1) doesn't deserve a scan.
	# Otherwise they'll all end up as files in RESULTPATH/extracted when all is done.
	find ./extracted/ -mindepth 2 -type f -name PKGBUILD | grep -v "openttd-bin-r" | parallel -j8 '
	VMHOSTPATH="'"$VMHOSTPATH"'"
	RESULTPATH="'"$RESULTPATH"'"
	VMGUESTPATH="'"$VMGUESTPATH"'"

	INPUTNAME="{}"
	DIRECTORYNAME="${INPUTNAME%/*}"
 	PACKAGENAME="${DIRECTORYNAME##*/}"

 	# If the last iteration stopped early, trust all full iterations.
 	# Archive could be incomplete if "doing-x" is still there.
 	if [[ ! -f "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME".tar ]] || [[ -f "$VMGUESTPATH"/tmp/doing-"$PACKAGENAME" ]]; then 
	 	CARCHS=(x86_64 i686)
	 	PKGPARAMS=(pkgname pkgver pkgrel pkgdir startdir srcdir epoch pkgbase pkgdesc arch url license groups depends optdepends makedepends checkdepends provides conflicts replaces backup options install changelog source noextract md5sums sha1sums sha256sums sha384sums sha512sums)
		# Flag if iteration completed to skip next time, since 40000 packages might take a couple of resumes.
		touch "$VMGUESTPATH"/tmp/doing-"$PACKAGENAME"
		for CARCH in "${CARCHS[@]}"
		do
			# Spawn a subshell so concealed exit 1 still allows second CARCH iteration.
			# ...and to check for PKGPARAMS only in the first CARCH (reset variables)
			touch "$VMGUESTPATH"/tmp/exitedearly-"$PACKAGENAME"-"$CARCH"
			(
			mkdir -p "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/
			SETBEFORE=$(compgen -v)
			source {} 1>"$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/stdout_$CARCH 2>"$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/stderr_$CARCH
			# Sourcing did not run an exit 1.  Good news.
			rm "$VMGUESTPATH"/tmp/exitedearly-"$PACKAGENAME"-"$CARCH"
			SETAFTER=$(compgen -v)

			# What variables did sourcing create, other than PKGPARAMS ones and _-prefixed?
			printf -v greppattern "^%s$\\|" "${PKGPARAMS[@]}"
			comm -13 <(printf "%b" "$SETBEFORE"|sort) <(printf "%b" "$SETAFTER"|sort) | grep -v "$greppattern^SETBEFORE$\|^_" >"$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/miscvars_$CARCH

			for param in ${PKGPARAMS[@]}
			do
				# Rather than specify which PKGPARAMS are arrays, just detect the declare -a switch.
				if declare -p "$param" 2>/dev/null | grep -q "^declare -a"; then
					# Indirectly accessing all elements of an array requires a temporary.
					TMPVAR="$param""[@]"
					printf "%b\n" "${!TMPVAR}" > "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/"$param"_$CARCH
				else
					printf "%b" "${!param}" > "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/"$param"_$CARCH 
				fi
			done
			)
		done

		# Some of the files made above will be accessing variables that never existed.
		find "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/ -type f -empty -exec rm -f \{\} \;

		# Add the package name as according to the directory it came out of, too, for later comparison.
		# The archive name, dirname and pkgname could all be different!
		# However, this dirname applies to both architectures of this file by definition.
		printf "%b" "$PACKAGENAME" >"$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/archivedir_both

		# Not a PKGBUILD param, so not looped over above, but use below for deduping.
		PKGPARAMS+=("miscvars" "stderr" "stdout")

		for param in ${PKGPARAMS[@]}
		do
			# If both architectures have the same exact file contents, just make one with arch _both.
			# TODO: Make it a loop that looks through CARCHS, and names the resultant _all.
			if cmp -s "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/"$param"_x86_64 "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/"$param"_i686; then
				rm "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/"$param"_x86_64
				mv "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/"$param"_i686 "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/"$param"_both
			fi
		done

		# When you finish with an application, tar it up.  Compression can happen later.
		# Stops tens of thousands of directories with dozens of files in (inode limitations).
		cd "$VMGUESTPATH"/tmp/aur/
		tar -cf "$PACKAGENAME.tar" "$PACKAGENAME"/
		rm -rf "$VMGUESTPATH"/tmp/aur/"$PACKAGENAME"/
		rm "$VMGUESTPATH"/tmp/doing-"$PACKAGENAME"
	fi
	'
}

archiveresults() {
	cd "$VMGUESTPATH"/tmp
	tar -zcf "$RESULTPATH"/exitedearly.tar.gz exitedearly-*
	cd ./aur
	tar -zcf "$RESULTPATH"/aur.tar.gz *.tar
	ls -al "$VMGUESTPATH" | grep -vP " (\.|\.\.|\.bash_history|extracted|tmp|pkgs|/media/sf_aur-things/|urls)$" > "$RESULTPATH"/dirmess
}

# cleanup
# genpkgs
# extractpkgs
# analyseall
# archiveresults