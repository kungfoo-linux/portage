# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# $Header$

prepman() {
	if [ -z "$1" ] ; then 
		z="${D}usr/share/man"
	else
		z="${D}$1/man"
	fi

	[ ! -d "${z}" ] && return 0
	
	for x in `find "${z}"/ -type d 2>/dev/null` ; do
		for y in `find "${x}"/ \( -type f -or -type l \) -maxdepth 1 -mindepth 1 2>/dev/null` ; do
			if [ -L "${y}" ] ; then
				# Symlink ...
				mylink="${y}"
				linkto="`readlink "${y}"`"
	
				if [ "${linkto##*.}" != "gz" ] ; then
					linkto="${linkto}.gz"
				fi
				if [ "${mylink##*.}" != "gz" ] ; then
					mylink="${mylink}.gz"
				fi
	
				echo "fixing man page symlink: ${mylink##*/}"
				ln -snf "${linkto}" "${mylink}" || die
				if [ "${y}" != "${mylink}" ] ; then
					echo "removing old symlink: ${y##*/}"
					rm -f "${y}" || die
				fi
			else
				if [ "${y##*.}" != "gz" ] ; then
					echo "gzipping man page: ${y##*/}"
					gzip -f -9 "${y}" || die
				fi
			fi	
		done
	done
}
