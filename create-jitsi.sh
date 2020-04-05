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
# License: CC-BY-SA 3.0
#cd ~
# Setup openstack environment
source .ostackrc.JITSI
# We need user settings in jitsi-user-$1.yml
if test -z "$1" -o ! -r "jitsi-user-$1.yml"; then echo "Usage: Pass USER (jitsi-user-USER.yml needs to exist)"; exit 1; fi
START=$(date +%s)
date
# If we interrupted, let's not recreate the stack, but just track progress
STATUS=$(openstack stack show jitsi-$1 -f value -c stack_status 2>/dev/null)
if test -z "$STATUS"; then
  # Copy config specific cert files
  if test -r cert-$1.crt; then
    cp -p cert-$1.crt cert.crt
    cp -p cert-$1.key cert.key
    openssl x509 -in cert.crt -noout -text | grep '\(DNS:\|CN\|Issuer:\|Not After\)'
  elif test ! -r cert.crt; then
    # Detect LETSENCRYPT usage
    if grep '^ *letsenc_mail:' jitsi-user-$1.yml >/dev/null 2>&1; then
      # We are using LetsEncrypt, empty cert files will do
      touch cert.crt
      touch cert.key
      chmod 0600 cert.key
    else
      echo "Need to provide cert-$1.crt and cert-$1.key."
      exit 3
    fi
  else
    openssl x509 -in cert.crt -noout -text | grep '\(DNS:\|CN\|Issuer:\|Not After\)'
  fi
  openstack stack create --timeout 21 -e jitsi-user-$1.yml -t jitsi-stack.yml jitsi-$1 || exit 2
  sleep 60
else
  echo "$STATUS"
fi
# We are not waiting for completion, let's rather use the time to watch and already set
# the public IP address, as it takes some time to propagate through DNS
JITSI_ADDRESS=$(openstack stack output show jitsi-$1 jitsi_address -f value -c output_value)
while test -z "$JITSI_ADDRESS"; do 
  sleep 10
  JITSI_ADDRESS=$(openstack stack output show jitsi-$1 jitsi_address -f value -c output_value)
done
echo "Jitsi address: $JITSI_ADDRESS"
# Optional .dyndns allows for updating Dynamic DNS server via REST call
PUB_DOM=$(grep ' public_domain:' jitsi-user-$1.yml | sed 's/^[^:]*: *\(.*\) *$/\1/')
unset DURL
if test -r .dyndns-$1; then source .dyndns-$1; elif test -r .dyndns; then source .dyndns; fi
# Keep this for backward compatibility
if test -n "$DURL"; then curl -k "$DURL"; fi
# Those two could contain sensitive data, so clear again
unset DPASS DURL
STATUS=$(openstack stack show jitsi-$1 -f value -c stack_status)
# Save private key
openstack stack output show jitsi-$1 private_key -c output_value -f value  > jitsi-$1.ssh
chmod 0600 jitsi-$1.ssh
ssh-keygen -R $JITSI_ADDRESS -f ~/.ssh/known_hosts
# Now watch the stack evolving
DISP=0
while test "$STATUS" != "CREATE_FAILED" -a "$STATUS" != "CREATE_COMPLETE"; do
  # Only output new lines (yes, there is a race, but this is for debugging/info only, so ignore
  LEN=$(ssh -o StrictHostKeyChecking=no -i jitsi-$1.ssh linux@$JITSI_ADDRESS sudo wc -l /var/log/cloud-init-output.log)
  LEN=${LEN%% *}
  if test -n "$LEN" -a "$LEN" != "$DISP"; then
    ssh -o StrictHostKeyChecking=no -i jitsi-$1.ssh linux@$JITSI_ADDRESS sudo tail -n $((LEN-DISP)) /var/log/cloud-init-output.log
    DISP=$LEN
  fi
  sleep 10
  STATUS=$(openstack stack show jitsi-$1 -f value -c stack_status)
done
# Now output results
STOP=$(date +%s)
openstack server list
LEN=$(ssh -o StrictHostKeyChecking=no -i jitsi-$1.ssh linux@$JITSI_ADDRESS sudo wc -l /var/log/cloud-init-output.log)
LEN=${LEN%% *}
if test $LEN != $DISP; then
  ssh -o StrictHostKeyChecking=no -i jitsi-$1.ssh linux@$JITSI_ADDRESS sudo tail -n $((LEN-DISP)) /var/log/cloud-init-output.log
  DISP=$LEN
fi
openstack stack list
date
if grep ' public_url:' jitsi-user-$1.yml >/dev/null 2>/dev/null; then 
  PUBLIC_URL=$(grep ' public_url:' jitsi-user-$1.yml | sed 's/^[^:]*: *\(.*\) *$/\1/')
else
  PUB_PRT=$(grep ' public_port:' jitsi-user-$1.yml | sed 's/^[^:]*: *\(.*\) *$/\1/')
  PUB_PRT=${PUB_PRT:-443}
  PUBLIC_URL="https://$PUB_DOM:$PUB_PRT/"
fi
echo "Deployed jitsi-$1 on $PUBLIC_URL ($JITSI_ADDRESS) in $((STOP-START))s"
