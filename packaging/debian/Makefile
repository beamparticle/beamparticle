# Author: Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>

VERSION ?= 0.1.0
ARCH ?= x86_64
COMPONENT ?= beamparticle
MAKEFILE_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PROD_TAR_PATH ?= $(MAKEFILE_PATH)/../../_build/prod/rel/$(COMPONENT)/$(COMPONENT)-$(VERSION).tar.gz

.PHONY: prepare package prepare-upgrade package-upgrade

prepare:
	rm -rf stage
	mkdir -p stage/opt/$(COMPONENT)-$(VERSION)/releases
	# copy current release to allow downgrade
	cp -f $(PROD_TAR_PATH) stage/opt/$(COMPONENT)-$(VERSION)/releases/
	tar -C stage/opt/$(COMPONENT)-$(VERSION) -xz -f $(PROD_TAR_PATH)
	mv stage/opt/$(COMPONENT)-$(VERSION)/releases/$(VERSION)/sys.config stage/opt/$(COMPONENT)-$(VERSION)/releases/$(VERSION)/sys.config.template
	mv stage/opt/$(COMPONENT)-$(VERSION)/releases/$(VERSION)/vm.args stage/opt/$(COMPONENT)-$(VERSION)/releases/$(VERSION)/vm.args.template
	mkdir -p stage/lib/systemd/system
	#mkdir -p stage/etc/systemd/system
	mkdir -p stage/DEBIAN
	cp -r systemd/$(COMPONENT).service stage/lib/systemd/system/$(COMPONENT).service
	cp -r systemd/$(COMPONENT).socket stage/lib/systemd/system/$(COMPONENT).socket
	sed -e 's/@VERSION@/$(VERSION)/g' control > stage/DEBIAN/control
	cp -f preinst stage/DEBIAN/
	sed -e 's/@VERSION@/$(VERSION)/g' postinst > stage/DEBIAN/postinst
	chmod 555 stage/DEBIAN/preinst
	chmod 555 stage/DEBIAN/postinst
	mkdir -p stage/etc/sysctl.d
	cp -f *sysctl.conf stage/etc/sysctl.d/
	mkdir -p stage/etc/security/limits.d
	cp -f *limits.conf stage/etc/security/limits.d/

package: prepare
	dpkg-deb --build stage $(COMPONENT)-$(VERSION)_$(ARCH).deb



prepare-upgrade:
	rm -rf stage-upgrade
	# releases/<relname>-<version>.tar.gz
	mkdir -p stage-upgrade/opt/$(COMPONENT)/releases
	cp -f $(PROD_TAR_PATH) stage-upgrade/opt/$(COMPONENT)/releases/
	chmod 444 stage-upgrade/opt/$(COMPONENT)/releases/$(COMPONENT)-$(VERSION).tar.gz
	mkdir -p stage-upgrade/DEBIAN
	sed -e 's/@VERSION@/$(VERSION)/g' control-upgrade > stage-upgrade/DEBIAN/control
	cp -f preinst-upgrade stage-upgrade/DEBIAN/preinst
	sed -e 's/@VERSION@/$(VERSION)/g' postinst-upgrade > stage-upgrade/DEBIAN/postinst
	chmod 555 stage-upgrade/DEBIAN/preinst
	chmod 555 stage-upgrade/DEBIAN/postinst

package-upgrade: prepare-upgrade
	dpkg-deb --build stage-upgrade $(COMPONENT)-upgrade-$(VERSION)_$(ARCH).deb

clean:
	rm -rf ./stage ./stage-upgrade
	rm -f *.deb

