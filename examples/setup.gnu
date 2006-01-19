#! /bin/sh -e
# $Id$
#
# This script builds the files necessary to configure this package for
# development.  Once you run this script, you will need GNU make,
# autoconf, and automake to build the software.  You must run "make
# dist" if you the wish to create a source tree that can be built
# without these tools.
#
# You should generally only need to run this script if you just
# checked sfs out of a CVS repository, or else somehow badly mangled
# the Makefile.

M4=gm4
$M4 --version < /dev/null 2>&1 | grep GNU >/dev/null 2>&1 || M4=gnum4
$M4 --version < /dev/null 2>&1 | grep GNU >/dev/null 2>&1 || M4=m4
$M4 --version < /dev/null 2>&1 | grep GNU >/dev/null 2>&1 \
    || (echo Cannot locate GNU m4 >&2; exit 1)

for file in Makefile.am.m4 */Makefile.am.m4; do
    if test -f $file; then
	out=`echo $file | sed -e 's/\.m4$//'`
	echo "+ $M4 $file > $out"
	rm -f $out~
	$M4 $file > $out~
	mv -f $out~ $out
    fi
done

autoreconf $*
