#!/bin/bash
# Cleanup OSISM Testbed on OTC needs a little help
# On a proper heat, just openstack stack delete jitsi-$1 would do the job.
# Usage: cleanup-otc.sh [USERNAME]
# STACKNAME defaults to the only deployed stack by default
# (c) Kurt Garloff <scs@garloff.de>, 2/2020, CC-BY-SA 3.0
#cd ~
source .ostackrc.JITSI
STACK=$(openstack stack list -f value -c "Stack Name" -c "Stack Status" | grep jitsi)
STACK_NM=${STACK%% *}
if test -z "$STACK_NM"; then echo "Could not find jitsi stack to delete."; exit 1; fi
if test -n "$1"; then
  # User might have passed not just USERNM but template filename
  if test -r "$1"; then USERNM="${1%.yml}"; USERNM="${USERNM##*-user-}"; else USERNM="$1"; fi
  if test "$STACK_NM" != "jitsi-$USERNM"; then
    echo "WARNING: Found $STACK_NM, but requesting deletion of jitsi-$USERNM"
    STACK_NM="jitsi-$USERNM"
  fi
else
  USERNM="${STACK_NM#jitsi-}"
fi
echo "Cleaning stack $STACK_NM"
if ! [[ "$STACK" == *"$STACK_NM"* ]]; then echo "No such stack $STACK_NM"; exit 2; fi
JITSI_ADDRESS=$(openstack stack output show ${STACK_NM} jitsi_address -f value -c output_value)
ssh -o StrictHostKeyChecking=no -i jitsi-$USERNM.ssh linux@$JITSI_ADDRESS sudo /root/down.sh
openstack stack delete -y --wait $STACK_NM
STACK=$(openstack stack list -f value -c "Stack Name" -c "Stack Status")
if ! [[ "$STACK" == *"$STACK_NM"* ]]; then exit 0; fi
openstack server list
openstack server delete $STACK_NM
STACK=$(openstack stack list -f value -c "Stack Name" -c "Stack Status")
if ! [[ "$STACK" == *"$STACK_NM"* ]]; then exit 0; fi
openstack stack delete -y --wait $STACK_NM
STACK=$(openstack stack list -f value -c "Stack Name" -c "Stack Status")
openstack stack list
if ! [[ "$STACK" == *"$STACK_NM"* ]]; then exit 0; fi
openstack security group delete $STACK_NM
openstack stack delete -y --wait $STACK_NM
echo "Stack should be gone now ..."
openstack stack list
STACK=$(openstack stack list -f value -c "Stack Name" -c "Stack Status")
if [[ "$STACK" == *"$STACK_NM"* ]]; then
  echo "Stack $STACK_NM still not gone"
  openstack stack show $STACK_NM -f value -c "stack_status_reason"
  openstack stack delete -y $STACK_NM
  exit 3
fi
