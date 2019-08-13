PMR2 VirtualBox Image generator
===============================

While there are independent instructions on how to put together the
complete PMR2 stack from scratch on running hardware, they are scattered
around the independent parts that compose the entire system.  While the
buildout does build the core completely, it however does not ensure the
rest of the operating system is at a state where this can even work, nor
does it touch upon the installation and setup of the additional backends
that the production instance now uses.

Instead of just providing documentation on how to build the whole thing,
having a script that does it all inside a virtual machine will serve the
purpose much better.  Not to mention that the result can be deployed as
a working instance either locally or onto a cloud computing platform.
The script was constructed based on documentation that was originally
done on top of Gentoo.

Do note that this relies on
`vboxtools <https://github.com/metatoaster/vboxtools>`_.  Documentation
on how these scripts actually work (and how to make them work) to come.
In brief, follow the instructions on creating a base Gentoo system, and
then call ``activatevm`` to spawn a new bash session.  Before executing
``gentoo/script.sh``, ensure that all relevant variables are filled with
a defined value.

Roughly speaking, the whole build process may be achieved by doing:

.. code-block:: console

    $ git clone https://github.com/metatoaster/vboxtools.git
    Cloning into 'vboxtools'...
    ...
    $ git clone https://github.com/PMR2/pmr2vbox.git
    Cloning into 'pmr2vbox'...
    ...
    $ # the create-gentoo command defaults to checking for the correct
    $ # signature of the downloaded images; the following commands will
    $ # acquire the right signatures; please verify this against the
    $ # Gentoo installation handbook linked in the documentation on the
    $ # landing page of the vboxtools repository
    $ gpg --keyserver hkp://keys.gnupg.net --recv-keys 0xBB572E0E2D182910
    gpg: requesting key 0xBB572E0E2D182910 from hkp server ...
    ...
    $ gpg --keyserver hkp://keys.gnupg.net --recv-keys 0xDB6B8C1F96D8BF6D
    gpg: requesting key 0xDB6B8C1F96D8BF6D from hkp server ...
    ...
    $ # create the vm; this process will take a while, a snack and/or
    $ # drink is suggested.
    $ vboxtools/bin/createvm-gentoo -U -n pmr_demo
    2018-10-04 16:00:00 URL:http://distfiles.gentoo.org/...
    ...
    gpg: Signature made Thu 04 Oct 2018 13:51:26 NZDT
    gpg:                using RSA key E1D6ABB63BFCFB4BA02FDF1CEC590EEAC9189250
    gpg: Good signature from "Gentoo ebuild repository signing key ...
    ...
    completing installation, removing installation script
    Waiting for VM "pmr_demo" to power on...
    VM "pmr_demo" has been successfully started.
    Once the VM is fully booted, connect to it with the following command:
        vboxtools/bin/connectvm "pmr_demo"
    ...
    $ # installation completed, but instead of connecting to the VM once
    $ # it fully boots up, it may be activated using:
    $ vboxtools/bin/activatevm pmr_demo
    spawning new shell (ctrl-d to exit)
    $ # the shell should actually be prefixed with the name of the VM
    $ # the prompt should appear as `(pmr_demo) $`
    $ pmr2vbox/gentoo/script.sh
     * Bringing up interface eth1
     *   dhcp ...
    ...

Once all that is done, it should result in a VirtualBox instance that
contain an instance with a base set of models.  The instance may be
opened with a web browser; one possible method is:

.. code-block:: console

    $ xdg-open http://${VBOX_IP}:8280/pmr

Alternatively, replace ``xdg-open`` with ``echo`` and then copy/paste
the URL to the address bar of a web browser.
