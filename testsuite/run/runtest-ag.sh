#! /bin/bash
# $Id$

YCP=$1
IN=$2
OUT_TMP=$3
ERR_TMP=$4
AG=$5

unset Y2DEBUG
unset Y2DEBUGGER

rm -f ntp.conf
cp tests.ag/ntp.conf .

shopt -s expand_aliases
alias kick-debug-lines="fgrep -v ' <0> '"
alias kick-empty-lines="grep -v '^$'"
alias strip-constant-part="sed 's/^....-..-.. ..:..:.. [^)]*) //g'"
alias mask-line-numbers="sed 's/^\([^ ]* [^)]*):\)[[:digit:]]*/\1XXX/'"

rm -f "$IN.test"
cp "$IN" "$IN.test" 2> /dev/null
AGDIR="`dirname $AG`"
ln -snf . "$AGDIR/servers_non_y2"

#multi
shopt -s nullglob
mkdir -p tmp/idir
rm -f tmp/idir/*
for INC in ${IN%.in}.*.d.in; do
    INC2=${INC##*/}
    INC2=${INC2#*.}
    cp $INC tmp/idir/${INC2%%.*}
done

Y=/usr/lib/YaST2/bin/y2base
Y2DIR="$AGDIR" $Y -l - 2>&1 >"$OUT_TMP" "$YCP" '("'"$IN.test"'")' testsuite \
    | kick-debug-lines \
    | kick-empty-lines \
    | strip-constant-part \
    | mask-line-numbers \
    > "$ERR_TMP"

cat "$IN.test" >> "$OUT_TMP" 2> /dev/null

#multi
for INC in ${IN%.in}.*.d.in; do
    INC2=${INC##*/}
    INC2=${INC2#*.}
    diff -u ${INC%.in}.out tmp/idir/${INC2%%.*} #2>&1
done

exit 0




# params:
# $1 "read" or "write"
# $2 input file name
# $3 output file name (template, expected)
# $4 output file name (temporary, actual)
# $5 agent commands file
# $6 full path of the agent to run
set -o errexit

# kludge: break up the output into lines
ADD_LF_BEFORE_MAP='s/\$\[/\
\$\[/g'
ADD_LF_AFTER_LAST_COMMA='s/,\] $/,\
\] /g'
ADD_LF_AFTER_COMMA_OR_COLON='s/\([:,]\)/\1\
/g'

NORMALIZE="parseycp -n"

function run() {
    IN=$2
    OUT=$3
    OUT_TMP=$4
    export IN OUT OUT_TMP
    sh $5 \
	| $NORMALIZE \
	| $6 \
	| $NORMALIZE \
	| sed -e 1d \
	| sed -e "$ADD_LF_BEFORE_MAP" -e "$ADD_LF_AFTER_LAST_COMMA" #-e "$ADD_LF_AFTER_COMMA_OR_COLON"
}

# MAIN
case $1 in
    read)
	run ${1+"$@"} > "$4"
	diff -u "$3" "$4"
	;;
    write)
	# test it twice - with the file existing and without it
#	rm -f "$4"
#	for i in 1 2; do
	    run ${1+"$@"} > /dev/null
	    diff -u "$3" "$4"
#	done
	;;
    *)
	echo "$0: Expecting 'read' or 'write' as \$1, got '$1'"
	exit 1
esac
