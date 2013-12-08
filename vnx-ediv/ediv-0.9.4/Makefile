MODULES_INSTALL_DEST=/usr/local/share/perl/5.8.8
BIN_DIR=/usr/local/bin
ETC_DIR=/usr/local/etc/ediv
DOC_DIR=/usr/local/share/doc/ediv
ALGO_DIR=/usr/local/share/ediv/algorithms
VER=0.9.4

TMP=/tmp

# In order to work, it it assumed the Makefile is in the
# ediv source root

# dh_make to create the initial debian/ directory:
#
# $DEBFULLNAME = "Mantainer Full Name"
# dh_make -c gpl
#         -e vnuml@dit.upm.es
#         -s

install:
	cp -av src/* $(BIN_DIR)
	mkdir -p $(ETC_DIR)
	cp -av etc/* $(ETC_DIR)
	mkdir -p $(DOC_DIR)
	cp -av doc/en/html $(DOC_DIR)
	cp CHANGELOG $(DOC_DIR)
	cp README $(DOC_DIR)
	mkdir -p $(MODULES_INSTALL_DEST)
	cp -av perl-modules/EDIV $(MODULES_INSTALL_DEST)
	mkdir -p $(ALGO_DIR)
	cp -av perl-modules/algorithms/* $(ALGO_DIR) 
	-find $(MODULES_INSTALL_DEST)/EDIV -type d -name CVS -exec rm -rf \{\} \; 2> /dev/null
	-find $(DOC_DIR) -type d -name CVS -exec rm -rf \{\} \; 2> /dev/null
	-find $(ETC_DIR) -type d -name CVS -exec rm -rf \{\} \; 2> /dev/null	

deb:
	mkdir -p $(TMP)/deb/ediv-$(VER)
	cp -a . $(TMP)/deb/ediv-$(VER)
	chmod 744 $(TMP)/deb/ediv-$(VER)/src/*
	-find $(TMP)/deb/ediv-$(VER) -type d -name CVS -exec rm -rf \{\} \; 2> /dev/null
	-find $(TMP)/deb/ediv-$(VER) -type f -name .project -exec rm -r \{\} \; 2> /dev/null
	-find $(TMP)/deb/ediv-$(VER) -type f -name .#\* -exec rm -r \{\} \; 2> /dev/null
	rm -rf $(TMP)/deb/ediv-$(VER)/debian
	cd $(TMP)/deb && tar cfz ediv-$(VER).tar.gz ediv-$(VER)/
	cd $(TMP)/deb/ediv-$(VER) && dh_make --single -f ../ediv-$(VER).tar.gz
	rm -rf $(TMP)/deb/ediv-$(VER)/debian
	cp -r debian $(TMP)/deb/ediv-$(VER)
	cd $(TMP)/deb/ediv-$(VER) && dpkg-buildpackage -rfakeroot

deb-clean:
	rm -rf $(TMP)/deb

uninstall:
	rm -fv $(BIN_DIR)/ediv_*
	rm -frv $(ETC_DIR)
	rm -frv $(DOC_DIR)
	rm -rfv $(MODULES_INSTALL_DEST)/EDIV	

modules-install:
	mkdir -p $(MODULES_INSTALL_DEST)/EDIV
	cp perl-modules/EDIV/* $(MODULES_INSTALL_DEST)/EDIV

modules-uninstall:
	rm -rf $(MODULES_INSTALL_DEST)/EDIV