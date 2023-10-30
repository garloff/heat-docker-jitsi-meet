#!/bin/bash
# check-jitsi.sh
# Checks whether Jitsi is accessible in the passed config
# If not, do either of two things:
# * Send an email to inform an admin
# * Delete the jitsi environment and recreate it
# The latter is the default.
# The former can be achieved by passing --inform [aka -i] EMAIL
# (c) Kurt Garloff <kurt@garloff.de>, 10/2023
# SPDX-License-Identifier: CC-BY-SA-4.0
#
THISDIR=$(dirname $0)
if test "$1" == "--inform" -o "$1" == "-i"; then WARNMAIL=$2; shift; shift; fi
# User might have passed not just USERNM but template filename
if test -r "$1"; then USERNM=${1%.yml}; USERNM=${USERNM##*-user-}; else USERNM=$1; fi
# We need user settings in jitsi-user-$USERNM.yml
USERCFG="jitsi-user-$USERNM.yml"
if test -z "$USERNM" -o ! -r "$USERCFG"; then echo "Usage: check-jitsi.sh USER (jitsi-user-USER.yml needs to exist)"; exit 1; fi
date
# Parse config file
PUBDOM=$(grep '^ *public_domain:' "$USERCFG" | sed 's/^ *public_domain: *\([^ ]*\) *$/\1/' | tr -d '"' | head -n1)
PUBPORT=$(grep '^ *public_port:' "$USERCFG" | sed 's/^ *public_port: *\([^ ]*\) *$/\1/' | tr -d '"' | head -n1)
# Test availability
echo "Check access to Jitsi at https://$PUBDOM:$PUBPORT/ ..."
timeout 12 openssl s_client -connect $PUBDOM:$PUBPORT -brief </dev/null
if test "$?" = 0; then echo "Everything looks good. Exit."; exit 0; fi
echo "ERROR"
# Error case
if test -z "$WARNMAIL"; then
	echo "Try restarting Jitsi ..."
	$(THISDIR)/cleanup-jitsi.sh $USERNM
	sleep 60
	$(THISDIR)/create-jitsi.sh $USERNM
else
	echo -e "From: Jitsi-Monitor <jitsi@$(hostname)>
Date: $(date -R)
Subject: Jitsi $PUBDOM:$PUBPORT down
To: $WARNMAIL

Dear administrator $WARNMAIL,

it appears that your Jitsi Service at https://$PUBDOM:$PUBPORT/
does not currently work. You may want to consider taking action.

-- 
Your friendly Jitsi Monitor <jitsi@$(hostname)>" | /usr/sbin/sendmail -f jitsi@$(hostname) $WARNMAIL
fi
