#!/bin/bash
# Setup a VM in OpenStack using heat to have a Jitsi deployment in docker containers.
# Leverage docker-jitsi-meet setup from jitsi
# Most of the logic is in jitsi-stack.yml
# To use it, you need to adjust a few things:
# * Get SSL certificates and drop them in cert.crt and cert.key. (key is sensitive, protect it!)
# * Create a jitsi-user-XXX.yml file and set jitsi_user, jitsi_password, public_url, 
#   letsenc_mail and letsenc_domain. (The latter two are unused by default, protect the yml file!)
# * You need to also define image_jitsi, flavor_jitsi, availability_zone and public
#   to match your cloud (unless you use the defaults that match OTC).
# * Optionally you can edit the script in the heat template to enable LETSENCRYPT and comment
#   out the copying in of the certificates. (Sorry, this should be configurabe as well.)
# * You need to have a .ostackrc.JITSI file that sets you environment variables such to make
#   the openstack command line tools work -- setting OS_CLOUD (plus settings in ~/.config/openstack/
#   clouds.yaml and secure.yaml) or old-style full set of OS_ variables.
# * Optionally set up a file .dyndns which is sourced and which can set a DURL variables for a
#   HTTP (REST) call to set up dynamic DNS. (The floating IP is allocated on the fly and will
#   thus change every time.
# * I used an openSUSE image that has a repo with current docker already configured. Except
#   for the SUSEfirewall2 disablement, there is not much you'd need to adjust to make it work
#   elsewhere. Be sure to not use any image that allows for ssh password auth, though ...
# * On some old heat implementations, you may need a cloud-init with PR#290 fixed in the image.
#
# That's all, have fun.
# TODO: I have not spend a lot of time to make this all nice, just minimal automation for my own
#  cron controlled automatic setup of Jitsi ...
# I have not moved anything outside the default meet.jitsi domain, so this will not look good
#  for official use.
# PRs are welcome, but I do not consider most limitations as bugs, so better send patches ...
#
# (c) Kurt Garloff <kurt@garloff.de>, 3/2020
# SPDX-License-Identifier: CC-BY-SA-4.0
#cd ~
# User might have passed not just USERNM but template filename
if test -r "$1"; then USERNM=${1%.yml}; USERNM=${USERNM##*-user-}; else USERNM=$1; fi
# We need user settings in jitsi-user-$USERNM.yml
if test -z "$USERNM" -o ! -r "jitsi-user-$USERNM.yml"; then
  echo "Usage: create-jitsi.sh USER (jitsi-user-USER.yml needs to exist)"
  exit 1
fi
# Setup openstack environment
if test -z "$OS_CLOUD" -a ! -r .ostackrc.$USERNM -a ! -r .ostackrc.JITSI; then
  echo "Create .ostackrc.$USERNM to configure your env for OpenStack access"
  exit 1
fi
if test -z "$OS_CLOUD" -a -r .ostackrc.$USERNM; then source .ostackrc.$USERNM; fi
if test -z "$OS_CLOUD" -a -r .ostackrc.JITSI; then source .ostackrc.JITSI; fi
START=$(date +%s)
date
# If we interrupted, let's not recreate the stack, but just track progress
STATUS=$(openstack stack show jitsi-$USERNM -f value -c stack_status 2>/dev/null)
if test -z "$STATUS"; then
  # Copy config specific cert files
  if test -r cert-$USERNM.crt; then
    cp -p cert-$USERNM.crt cert.crt
    cp -p cert-$USERNM.key cert.key
    openssl x509 -in cert.crt -noout -text | grep '\(DNS:\|CN\|Issuer:\|Not After\)'
  elif test ! -r cert.crt; then
    # Detect LETSENCRYPT usage
    if grep '^ *letsenc_mail:' jitsi-user-$USERNM.yml >/dev/null 2>&1; then
      # We are using LetsEncrypt, empty cert files will do
      touch cert.crt
      touch cert.key
      chmod 0600 cert.key
    else
      echo "Need to provide cert-$USERNM.crt and cert-$USERNM.key."
      # FIXME: Call ./sendalarm.sh here as well?
      exit 3
    fi
  else
    openssl x509 -in cert.crt -noout -text | grep '\(DNS:\|CN\|Issuer:\|Not After\)'
  fi
  if test -r watermark-$USERNM.svg; then
    gzip -c watermark-$USERNM.svg > watermark.svg.gz
  elif test -r watermark-$USERNM.png; then
    gzip -c watermark-$USERNM.png > watermark.svg.gz
  else
    touch watermark.svg.gz
  fi
  if test -r favicon-$USERNM.ico; then
    gzip -c favicon-$USERNM.ico > favicon.ico.gz
  else
    touch favicon.ico.gz
  fi
  # Prepare heat replacement
  OS_CAT=$(openstack catalog list -f json)
  OS_HEAT_INT=$(echo "$OS_CAT" | jq '.[]|select(.Type=="orchestration")|.Endpoints[]|select(.interface=="internal")|.url' | tr -d '"')
  OS_HEAT_PUB=$(echo "$OS_CAT" | jq '.[]|select(.Type=="orchestration")|.Endpoints[]|select(.interface=="public")|.url'  | tr -d '"')
  OS_HEAT_INT=${OS_HEAT_INT%/*}
  OS_HEAT_PUB=${OS_HEAT_PUB%/*}
  EXC='!'
  echo -e "#${EXC}/bin/bash\nsed \"s@$OS_HEAT_INT@$OS_HEAT_PUB@\" -i /root/run.sh" > heat-public-ep.sh
  # Create keypair
  rm -f keypair-jitsi-$USERNM keypair-jitsi-$USERNM.pub
  ssh-keygen -q -C jitsi-$USERNM -t ed25519 -N "" -f keypair-jitsi-$USERNM || return 1
  PUBKEY="$(cat keypair-jitsi-$USERNM.pub)"
  # External network
  if ! grep '^ *public:' jitsi-user-$USERNM.yml >/dev/null; then
    EXT_NET=$(openstack network list --external -f value -c Name | head -n1)
    PARAMS="--parameter public=${EXT_NET}"
  fi
  if ! grep '^ *availability_zone:' jitsi-user-$USERNM.yml >/dev/null; then
    AZ=$(openstack availability zone list --compute -f value -c "Zone Name" -c "Zone Status" | grep available | head -n1 | cut -d" " -f1)
    if test -n "$AZ"; then PARAMS="$PARAMS --parameter availability_zone=$AZ"; fi
  fi
  if ! grep '^ *wants_volume:' jitsi-user-$USERNM.yml >/dev/null; then
    FLV=$(grep '^ *flavor_jitsi:' jitsi-user-$USERNM.yml | sed 's/^ *flavor_jitsi: \([^#]*\)$/\1/' | tr -d '"')
    if test -z "$FLV"; then FLV=$(grep -A7 '^ *flavor_jitsi:' jitsi-stack.yml | grep '^ *default:' | head -n1 | sed 's/^ *default: \(.*\)$/\1/' | tr -d '"'); fi
    DISKSIZE=$(openstack flavor show $FLV -f json | jq '.disk')
    if test -n $DISKSIZE -a $DISKSIZE -gt 0; then PARAMS="$PARAMS --parameter wants_volume=false"; fi
  fi
  echo openstack stack create --timeout 26 --parameter pubkey="$PUBKEY" $PARAMS -e jitsi-user-$USERNM.yml -t jitsi-stack.yml jitsi-$USERNM
  openstack stack create --timeout 26 --parameter pubkey="$PUBKEY" $PARAMS -e jitsi-user-$USERNM.yml -t jitsi-stack.yml jitsi-$USERNM
  if test $? != 0; then
    echo "openstack stack create FAILED for $USERNM"
    if test -x ./sendalarm.sh; then
      ./sendalarm.sh NOCREATE $USERNM 0
    fi
    exit 2
  fi
  sleep 60
else
  echo "$STATUS"
fi
# Determine image username
IMG=$(grep '^ *image_jitsi:' jitsi-user-$USERNM.yml | sed 's/^ *image_jitsi: \([^#]*\)$/\1/' | tr -d '"')
if test -z "$IMG"; then IMG=$(grep -A6 '^ *image_jitsi:' jitsi-stack.yml | grep '^ *default:' | sed 's/^ *default: \(.*\)$/\1/' | tr -d '"'); fi
IMG_USER=$(openstack image show "$IMG" -f json | jq '.properties.image_original_user' | tr -d '"')
if test -z "$IMG_USER" -o "$IMG_USER" = "null"; then IMG_USER=$(echo "${IMG%% *}" | tr 'A-Z' 'a-z'); fi
# We are not waiting for completion, let's rather use the time to watch and already set
# the public IP address, as it takes some time to propagate through DNS
JITSI_ADDRESS=$(openstack stack output show jitsi-$USERNM jitsi_address -f value -c output_value)
while test -z "$JITSI_ADDRESS"; do 
  sleep 10
  JITSI_ADDRESS=$(openstack stack output show jitsi-$USERNM jitsi_address -f value -c output_value)
done
echo "Jitsi address: $JITSI_ADDRESS"
# Optional .dyndns allows for updating Dynamic DNS server via REST call
PUB_DOM=$(grep ' public_domain:' jitsi-user-$USERNM.yml | sed 's/^[^:]*: *\(.*\) *$/\1/')
STATUS=$(openstack stack show jitsi-$USERNM -f value -c stack_status)
ssh-keygen -R $JITSI_ADDRESS -f ~/.ssh/known_hosts
ssh-keygen -R $PUB_DOM -f ~/.ssh/known_hosts 
if grep '^ *letsenc_mail:' jitsi-user-$USERNM.yml >/dev/null 2>&1; then
  # Set the DNS entry already, so acme can succeed
  unset DURL
  if test -r .dyndns-$USERNM; then source .dyndns-$USERNM; elif test -r .dyndns; then source .dyndns; fi
  # Keep this for backward compatibility
  if test -n "$DURL"; then curl -k "$DURL"; fi
  # Those two could contain sensitive data, so clear again
  unset DPASS DURL
fi
# Now watch the stack evolving
DISP=0
declare -i STALL=0
while test "$STATUS" != "CREATE_FAILED" -a "$STATUS" != "CREATE_COMPLETE"; do
  # Only output new lines (yes, there is a race, but this is for debugging/info only, so ignore
  LEN=$(ssh -o StrictHostKeyChecking=no -i keypair-jitsi-$USERNM $IMG_USER@$JITSI_ADDRESS sudo wc -l /var/log/cloud-init-output.log)
  LEN=${LEN%% *}
  if test -n "$LEN" -a "$LEN" != "$DISP"; then
    ssh -o StrictHostKeyChecking=no -i keypair-jitsi-$USERNM $IMG_USER@$JITSI_ADDRESS sudo tail -n $((LEN-DISP)) /var/log/cloud-init-output.log
    STALL=0
    DISP=$LEN
  else
    let STALL+=1
    if test $STALL == 10; then
      NOW=$(date +%s)
      echo "ALARM: Deployment $USERNM stalled since 100s (@$(($NOW-$START)))"
      if test -x ./sendalarm.sh; then ./sendalarm.sh STALL $USERNM $(($NOW-$START)); fi
    fi
  fi
  sleep 10
  STATUS=$(openstack stack show jitsi-$USERNM -f value -c stack_status)
done
if test "$STATUS" != "CREATE_COMPLETE"; then
  openstack stack show jitsi-$USERNM -c stack_status_reason -f value
  echo "DNS not redirected to $JITSI_ADDRESS for $PUB_DOM"
else
  if ! grep '^ *letsenc_mail:' jitsi-user-$USERNM.yml >/dev/null 2>&1; then
    unset DURL
    if test -r .dyndns-$USERNM; then source .dyndns-$USERNM; elif test -r .dyndns; then source .dyndns; fi
    # Keep this for backward compatibility
    if test -n "$DURL"; then curl -k "$DURL"; fi
    # Those two could contain sensitive data, so clear again
    unset DPASS DURL
  fi
fi
# Now output results
STOP=$(date +%s)
openstack server list
LEN=$(ssh -o StrictHostKeyChecking=no -i keypair-jitsi-$USERNM $IMG_USER@$JITSI_ADDRESS sudo wc -l /var/log/cloud-init-output.log)
LEN=${LEN%% *}
if test $LEN != $DISP; then
  ssh -o StrictHostKeyChecking=no -i keypair-jitsi-$USERNM $IMG_USER@$JITSI_ADDRESS sudo tail -n $((LEN-DISP)) /var/log/cloud-init-output.log
  DISP=$LEN
fi
openstack stack list
date
if grep ' public_url:' jitsi-user-$USERNM.yml >/dev/null 2>/dev/null; then 
  PUBLIC_URL=$(grep ' public_url:' jitsi-user-$USERNM.yml | sed 's/^[^:]*: *\(.*\) *$/\1/')
else
  PUB_PRT=$(grep ' public_port:' jitsi-user-$USERNM.yml | sed 's/^[^:]*: *\(.*\) *$/\1/')
  PUB_PRT=${PUB_PRT:-443}
  PUBLIC_URL="https://$PUB_DOM:$PUB_PRT/"
fi
echo "Deployed jitsi-$USERNM on $PUBLIC_URL ($JITSI_ADDRESS) in $((STOP-START))s: $STATUS"
if test "$STATUS" == "CREATE_FAILED" -a -x ./sendalarm.sh; then
	./sendalarm.sh FAILED $USERNM $(($STOP-$START))
fi
