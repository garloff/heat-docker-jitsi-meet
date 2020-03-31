# heat-docker-jitsi-meet
Some heat automation around the docker-jitsi-meet containers.

If you have access to an OpenStack cloud with heat, this will make deployment
of a Jitsi Meet server fairly easy -- thanks to the great docker continer work
from the jitsi project. Obviously, you could just rebuild and redeploy the
docker container all the time ... but if you are on a cloud, chances are that
you pay for the running VM and the public IP address, so creating it on demand
is what these scripts and templates solve for you.

## Configuration

* Create a ``jitsi-user-XXX.yml`` file and set ``jitsi_user``, ``jitsi_password``, 
  ``public_domain``, ``public_port``. If you want set ``letsenc_mail``, the deployment stack
  will auto-generate Let's Encrypt certs. You can set ``letsenc_domain`` then as well (defaults
  to ``public_domain``).
  You can override ``public_url``, it will otherwise default to ``https://<public_domain>:<public_port>/``.
  Protect this file, as it will contain the ``jitsi_password``.

* If you don't use Let's Encrypt, you need to provide valid SSL certificates in ``cert.crt`` 
  and ``cert.key`` for https to work. Protect ``cert.key``. If you do use Let's Encrypt, those 
  files still need to exist, but you can use empty files -- they won't get used.

* You need to also define ``image_jitsi``, ``flavor_jitsi``, ``availability_zone`` and ``public``
  (the network from which to allocate public floating IPs from) to match your cloud.
  The defaults are from OTC.

* Optionally set up a file ``.dyndns`` which is sourced and which can set a ``DURL`` variable 
  for a HTTP (REST) call to set up dynamic DNS. (The floating IP is allocated on the fly and will
  thus change every time.

* Optionally, you can use ``tweak_ideal_height`` to set a lower default resolution than 720p.
  You can try ``540``, ``480`` or ``360`` if you have many participants with limited bandwidth (or 
  run into server upstream bandwidth limitations for large conferences).

## Requirements

* You need to have a ``.ostackrc.JITSI`` file that sets your environment variables such to make
  the openstack command line tools work -- setting ``OS_CLOUD`` (plus settings in 
  ``~/.config/openstack/clouds.yaml`` and ``secure.yaml``) or old-style full set of ``OS_`` 
  variables.

* I used an openSUSE image that has a repo with current docker already configured. Except
  for the SUSEfirewall2 disablement and the default username, there is not much you'd need
  to adjust to make it work elsewhere. Be sure to not use any image that allows for ssh
  password auth, though, if you are interested in not becoming a target for hackers ...

* On some old heat implementations (including OTC's), you may need a cloud-init with PR#290 
  fixed in the image.

## Usage

After checking prerequisites and filling in the configuration (see templates),
run ``./create-jitsi.sh USERNM`` to create a stack with the ``jitsi-user-USERNM.yml``
environment configuration. The script will output the progress on the created server.

The ``cleanup-jitsi.sh USERNM`` is only required if your heat implementation struggles
to clean up everything properly. which I have only seen on OTC.

After you have deployed the stack successfully, you can connect to the endpoint as
defined in ``public_url``. Guests can join open rooms, but rooms can only be activated
by authenticated users -- the one that is defined in your ``jitsi-user-USERNM.yml``
file.

You can access the server afterwards with ``ssh -i jitsi-USERNM.ssh linux@FIP``,
where you replace ``USERNM`` with the username used above, ``FIP`` with the floating
IP address assigned to the server and ``linux`` with the default username of the image.

Get root and use ``docker exec -it root_prosody_1 prosodyctl --config /config/prosody.cfg.lua adduser USERNM@meet.jitsi``
on this server to deploy another authenticated user that can create rooms.

Refer to the docker-jitsi-meet(https://github.com/jitsi/docker-jitsi-meet/) documentation
for more info.

## License

Use it under the terms of the Creative Commons with attribution and share-alike 3.0 terms.
(CC BY-SA 3.0).
