#!/bin/bash

genlist() {
	if [[ ! -f res/checkurls ]]; then
		find ./res/aur -type f -name "source_*" -exec cat {} \; -exec echo \; | grep "://" | sed 's/^.*:://' | cat - <(find ./res/aur -type f -name "url_*" -exec cat {} \; -exec echo \;) | sed 's|/$||' | awk 'BEGIN{RS=ORS="\n"}!a[$0]++' > res/checkurls
	elif [[ -f res/goodurls ]]; then
		comm -23 <(cat res/checkurls|sort) <(cat res/goodurls|sort) > res/checkurls.tmp
		rm res/checkurls res/goodurls
		mv res/checkurls.tmp res/checkurls
	fi
}

runcheck() {
	cat res/checkurls | parallel -N 50 -j8 '
	URLS=( {} )
	UA="Mozilla/5.0 (X11; Linux i686; rv:21.0) Gecko/20100101 Firefox/21.0"
	for URL in ${URLS[@]}
	do
		URLMINUSHINT=${URL#*+}
		PROTOCOL=${URL%%://*}
		HINT=${URL%%+*}
		if [[ "$URL" != "" ]]; then
			case $PROTOCOL in
				"http" | "https")
					GOODURL=false; BADURL=false; QUERY1=""; QUERY2=""
					QUERY1=$(curl -A "$UA" -m 10 -kLo /dev/null --silent --head --write-out %{http_code} -- $URL)
					ERRCODE=$?
					{ [[ "$QUERY1" -ge 200 ]] && [[ "$QUERY1" -lt 300 ]]; } && GOODURL=true
					{ [[ $ERRCODE -eq 3 ]] || [[ $ERRCODE -eq 6 ]] } && BADURL=true
					! $GOODURL && ! $BADURL && QUERY2=$(curl -A "$UA" -m 10 -kLo /dev/null --silent --header "Range: bytes=0-1" --write-out %{http_code} -- $URL)
					{ [[ "$QUERY2" -ge 200 ]] && [[ "$QUERY2" -lt 300 ]]; } && GOODURL=true
					# A potential QUERY3 will be curl -IX GET.
					# Blame falconindy in curl IRC.
					# 20:20 falconindy | you can use -I -X GET
					# 20:20 falconindy | which makes curl misbehave a little bit, but it seems to work
					# 20:21 falconindy | * Excess found in a non pipelined read: excess = 3461 url = / (zero-length body)
					# 20:21 falconindy | but it isn`t an error 

					if $GOODURL; then
						echo "$URL"
					elif { ! $BADURL && [[ "$QUERY1" != "404" ]] && [[ "$QUERY1" != "401" ]] && [[ "$QUERY2" != "404" ]] && [[ "$QUERY2" != "401" ]]; }; then
						echo "$QUERY1 $QUERY2 $URL" >&2
					fi
					;;
				"ftp")
					[[ $(curl -m 10 -Lo /dev/null --silent --head --write-out %{http_code} -- $URL) == 350 ]] && echo "$URL"
					;;
				"git")
					git ls-remote "${URL%%#*}" &>/dev/null && echo "$URL"
					;;
				"svn")
					svn ls -- ${URL%%#*} &>/dev/null && echo "$URL"
					;;
				"bzr")
					bzr revno -- ${URL%%#*} &>/dev/null && echo "$URL"
					;;
				"hg")
					hg id -r tip -- ${URL%%#*} &>/dev/null && echo "$URL"
					;;
				"local" | "file")
					echo "$URL"
					;;
				"rsync")
					rsync --list-only -- rsync://rsync.samba.org/rsyncftp/tech_report.fffps &>/dev/null && echo "$URL"
					;;
				"hib")
					echo "$URL"
					;;
				*)
					case $HINT in
						"git")
							git ls-remote "${URLMINUSHINT%%#*}" &>/dev/null && echo "$URL"
							;;
						"svn")
							svn ls -- ${URLMINUSHINT%%#*} &>/dev/null && echo "$URL"
							;;
						"bzr")
							bzr revno -- ${URLMINUSHINT%%#*} &>/dev/null && echo "$URL"
							;;
						"hg")
							hg id -r tip -- ${URLMINUSHINT%%#*} &>/dev/null && echo "$URL"
							;;
						*)
							echo "$URL" >&2
							# echo "{}: Unknown protocol $PROTOCOL."
							;;
					esac
					;;
			esac
		else
			echo "$URL"
		fi
	done
	' > res/goodurls
}

RUNCHECK=true
while getopts ":m" opt; do
	case $opt in
	m)
		# Merge only.
		RUNCHECK=false
		;;
	esac
done

genlist
$RUNCHECK && runcheck