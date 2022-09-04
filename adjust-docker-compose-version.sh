#!/bin/bash
# Adjust docker compose versions: They all need to match.
# We align jigasi.yml and etherpad.yml with docker-compose.yml.
# (c) Kurt Garloff <kurt@garloff.de>, 7/2022
# SPDX-License-Identifier: CC-BY-SA-4.0

getver()
{
	grep ^version $1
}

adjustver()
{
	LVER=$(getver $2)
	if test "$1" != "$LVER"; then
		echo "Adjust $2 from $LVER to $1" 1>&2
		sed -i "s/$LVER/$1/g" $2
	fi
}

cd /root

DCVER=$(getver docker-compose.yml)

adjustver "$DCVER" jigasi.yml
adjustver "$DCVER" etherpad.yml

