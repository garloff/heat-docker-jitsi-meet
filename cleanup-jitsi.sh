#!/bin/bash
# Cleanup OSISM Testbed on OTC needs a little help
# On a proper heat, just openstack stack delete jitsi-$1 would do the job.
# Usage: cleanup-otc.sh [USERNAME]
# STACKNAME defaults to the only deployed stack by default
# (c) Kurt Garloff <scs@garloff.de>, 2/2020, CC-BY-SA 3.0
#cd ~
if test -r "$1"; then USERNM="${1%.yml}"; USERNM="${USERNM##*-user-}"; else USERNM="$1"; fi
if test -z "$OS_CLOUD" -a -r ",ostackrc.$USERNM"; then source .ostackrc.$USERNM; fi
if test -z "$OS_CLOUD" -a -r ",ostackrc.JITSI"; then source .ostackrc.JITSI; fi
STACK=$(openstack stack list -f value -c "Stack Name" -c "Stack Status" | grep jitsi)
STACK_NM=${STACK%% *}
if test -z "$STACK_NM"; then echo "Could not find jitsi stack to delete."; exit 1; fi
if test -n "$1"; then
  # User might have passed not just USERNM but template filename
  if test "$STACK_NM" != "jitsi-$USERNM"; then
    echo "WARNING: Found $STACK_NM, but requesting deletion of jitsi-$USERNM"
    STACK_NM="jitsi-$USERNM"
  fi
else
  USERNM="${STACK_NM#jitsi-}"
fi
echo "Cleaning stack $STACK_NM"
if ! [[ "$STACK" == *"$STACK_NM"* ]]; then echo "No such stack $STACK_NM"; exit 2; fi
# Determine image username
IMG=$(grep '^ *image_jitsi:' jitsi-user-$USERNM.yml | sed 's/^ *image_jitsi: \([^#]*\)$/\1/' | tr -d '"')
if test -z "$IMG"; then IMG=$(grep -A6 '^ *image_jitsi:' jitsi-stack.yml | grep '^ *default:' | sed 's/^ *default: \(.*\)$/\1/' | tr -d '"'); fi
IMG_USER=$(openstack image show "$IMG" -f json | jq '.properties.image_original_user' | tr -d '"')
if test -z "$IMG_USER" -o "$IMG_USER" = "null"; then IMG_USER=$(echo "${IMG%% *}" | tr 'A-Z' 'a-z'); fi
JITSI_ADDRESS=$(openstack stack output show ${STACK_NM} jitsi_address -f value -c output_value)
ssh -o "ConnectTimeout=12" -o "StrictHostKeyChecking=no" -i keypair-jitsi-$USERNM $IMG_USER@$JITSI_ADDRESS sudo /root/down.sh
openstack stack delete -y --wait $STACK_NM
rm -f $STACK_NM $STACK_NM.pub
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
openstack volume delete $STACK_NM >/dev/null 2>&1
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
