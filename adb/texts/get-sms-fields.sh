#!/bin/bash

if ! test "$1" -gt 0 2>/dev/null; then
        echo "Usage: $0 _id"
        exit 1
fi

DIR="$(pwd)"
cd "$DIR" || exit 2

ID="$1"
OUTFILE="$ID-fields.txt"
{
        DATA=$(adb shell "content query --uri content://sms/${ID}")
	echo "$DATA" | sed 's/,/\n/g' | sed 's/^ \([a-z_]*\)=.*$/\1/' | grep -v 'body' | tail -n +2
} > "$OUTFILE"
