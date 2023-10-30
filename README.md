# heat-docker-jitsi-meet
Some heat automation around the docker-jitsi-meet containers.

If you have access to an OpenStack cloud with heat, this will make deployment
of a Jitsi Meet server fairly easy -- thanks to the great docker continer work
from the jitsi project. Obviously, you could just rebuild and redeploy the
docker container all the time ... but if you are on a cloud, chances are that
you pay for the running VM and the public IP address, so creating it on demand
is what these scripts and templates solve for you.

## Configuration

* Create a ``jitsi-user-USERNM.yml`` file and set ``jitsi_user``, ``jitsi_password``, 
  ``public_domain``, ``public_port``. You can deploy multiple users by providing a
  space-separated list of users and passwords.
  If you want set ``letsenc_mail``, the deployment stack
  will auto-generate Let's Encrypt certs. You can set ``letsenc_domain`` then as well (defaults
  to ``public_domain``). The ``USERNM`` is an identifier for a specific config, as it contains
  the ``jitsi_user``, I suggest to tie its naming to it.
  You can override ``public_url``, it will otherwise default to ``https://<public_domain>:<public_port>/``.
  You can override the ``timezone`` and the default ``ui_language`` also.
  Protect this file, as it will contain the ``jitsi_password``.

* If you don't use Let's Encrypt, you need to provide valid SSL certificates in ``cert-USERNM.crt`` 
  and ``cert-USERNM.key`` for https to work. Protect ``cert.key``. If you do use Let's Encrypt, you
  don't need them. Unless you do some redirection to forward port 80 to 8000, you will need to change
  the ``letenc_http_port`` setting to 80 to make the acme-challenge succeed. 

* You need to also define ``image_jitsi``, ``flavor_jitsi``, ``availability_zone`` and ``public``
  (the network from which to allocate public floating IPs from) to match your cloud.
  The defaults are working on CityCloud, OTC specific changes are commented out.

* Optionally set up a file ``.dyndns-USERNM`` which is sourced (called).
  This can be used to do do a call to register your public IP address (in ``JITSI_ADDRESS``)
  with a DynDNS provider or designate or whatever mechanism you want to use to create a
  DNS entry for your newly acquired floating IP address. The script also gets the environment
  variable ``PUB_DOM`` containing the public domain name.
  (For compatibility reasons: If the script sets a ``DURL`` variable, it will be used in a curl
  call from the main script. Also, if no ``.dyndns-USERNM`` file exists, the script looks for
  ``.dyndns``.)

* Optionally, you can use ``tweak_ideal_height`` to set a lower default resolution than 720p.
  You can try ``540``, ``480`` or ``360`` if you have many participants with limited bandwidth (or 
  run into server upstream bandwidth limitations for large conferences). If you use ``tweak_ideal_height``,
  a few more adjustments are made: the minimal height is lowered to 180, SimulCast is enabled (which
  is default anyway) and LayerSuppresion is enabled (not enabled by default). You can also use
  ``tweak_channelLastN`` allows you to limit the number of videos streams (from the last N speakers)
  to be active, default is ``-1`` (unlimited).

* Optionally you can start SIP integration (jigasi) by specifying ``jigasi_sip_uri`` and
  ``jigasi_sip_password``. Optionally, you can override the defaults for ``jigasi_sip_server``
  (extracted from the uri by default), ``jigasi_sip_transport`` (UDP) and ``jigasi_sip_port`` 
  (5060). To allow dial-in from a standard line (not sending special ``X-Room-Name`` SIP headers),
  you can specify a ``jigasi_default_room``.

* Optionally, you can drop files ``watermark-USERNM.svg`` and/or ``favicon-USERNM.ico``, which
  will be used to replace the default jitsi icons. Specifying ``jitsi_watermark_link`` will
  change the default link from the watermark icon (top left) from ``https://jitsi.org`` to
  a location of your desire. Note that the size of injected files is limited on many OpenStack
  clouds -- which is why the files are gzipped (but this only helps for non-already well compressed
  file formats, such as .ico.

## Requirements

* You need to have a ``.ostackrc.JITSI`` file that sets your environment variables such to make
  the openstack command line tools work -- setting ``OS_CLOUD`` (plus settings in 
  ``~/.config/openstack/clouds.yaml`` and ``secure.yaml``) or old-style full set of ``OS_`` 
  variables.

* I used an openSUSE image that has a repo with current docker already configured. Except
  for the SUSEfirewall2 disablement and the default username, there is not much you'd need
  to adjust to make it work elsewhere. Be sure to not use any image that allows for ssh
  password auth, though, if you are interested in not becoming a target for hackers ...
  Find my image on http://kfg.images.obs-website.eu-de.otc.t-systems.com/

* On some old heat implementations (including OTC's), you may need a cloud-init with PR#290 
  fixed in the image.

* The deployment allocates a floating IP address to expose the Jitsi service on. You need to
  have access to some domain and feed the IP address to the DNS service, via some DynDNS
  or designate or similar protocol -- the magic is done in the ``.dnydns`` file. You can
  provide SSL certs or use the Let's Encrypt magic to get certs on the fly. (Obviously,
  you can also work with IP addresses, but I can't recommend this.)

## Usage

After checking prerequisites and filling in the configuration (see templates),
run ``./create-jitsi.sh USERNM`` to create a stack with the ``jitsi-user-USERNM.yml``
environment configuration. The script will output the progress on the created server.
It will typically run for roughly 10mins.

The ``cleanup-jitsi.sh USERNM`` is only required if your heat implementation struggles
to clean up everything properly, which I have only seen on OTC. Otherwise you can also
simply use an ``openstack stack delete jitsi-USERNM``.

After you have deployed the stack successfully, you can connect to the endpoint as
defined in ``public_url`` (defaults to https://``public_domain``:``public_port``/).
In the configured setup, guests can join open rooms, but rooms can only be activated
by authenticated users -- the one that is defined in your ``jitsi-user-USERNM.yml``
file. Use ``USERNM`` here. (The domain ``@meet.jitsi`` is implied here.)

You can access the server afterwards with ``ssh -i jitsi-USERNM.ssh linux@FIP``,
where you replace ``USERNM`` with the username used above, ``FIP`` with the floating
IP address assigned to the server and ``linux`` with the default username of the image.
(Obviously instead of FIP, you can use the DNS name that you need to register anyway,
so ``ssh -i jitsi-USERNM.ssh linux@public_domain``.)

Inside the VM, you can do useful things such as looking at the docker logs or
becoming root and using
``docker exec -it root-prosody-1 prosodyctl --config /config/prosody.cfg.lua adduser USERNM2 meet.jitsi PASSWD2``
to deploy another authenticated user that can create rooms.

However, it is not recommended to login to container and do changes -- they are not persistent and
won't survive a container restart. So rather use the ``jitsi-user-USERNM.yml`` configuration
to have several users. In my setup, I redeploy the container every night to have fresh state and
current software.

Refer to the docker-jitsi-meet(https://github.com/jitsi/docker-jitsi-meet/) documentation
for more info.

## TODO

* Allow for more than one user to be registered on installation.

* Watch out for more tweaks to deal with limited bandwidth for large conferences.

* Support pre-allocated floating IP address to allow for pseudo-static DNS setup.

* Prepare for other more generic images.

* Allow tweaking internal domain name which is currently defaulting to meet.jitsi.

* I have a script that sets up traffic shaping with HTB which might be useful. Adjust it,
  test it and integrate if it turns out to be helpful.

* Harvest LetsEnc certificate for reuse, but watch expiry.

Contributions (ideally as Pull Requests) are welcome!

## License

Use it under the terms of the Creative Commons with attribution and share-alike 3.0 terms.
(CC BY-SA 3.0).
