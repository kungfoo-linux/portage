# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# $Header$

dohtml() {
	dohtml.py "$@" || die "dohtml filed"
}
