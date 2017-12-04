.. _download_and_install:

============
Installation
============

Requirements
============

* Debian_ or Ubuntu_ 16.04+

Optional:

.. _Debian: http://www.debian.org/
.. _Ubuntu: http://www.ubuntu.com/


Installation 
============

Debian or Ubuntu
----------------

There is a deb package (beamparticle-<ver>_x86_64.deb), which directly installs on
base Debian 9 or Ubuntu system (16.04+).

.. _download:

Building from source
====================

The following packages must be installed otherwise the NIF (c code) for
eleveldb will fail to build. Note that libssl-dev is required
by snappy (a requirement of eleveldb).

    sudo apt-get install build-essential
    sudo apt-get install libssl-dev

Code
----

The development uses git version control and the code can be cloned
as follows:

	git clone https://github.com/beamparticle/beamparticle

Building the deb package
------------------------

Building the package is wrapped in a make target.
 
	make deb-package
