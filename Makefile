# the current Cricket version number
VER=1.1.0

# we use Perforce to control this stuff internally.
P4=p4

DISTDIR=../cricket-$(VER)
DISTTAR=../cricket-$(VER).tar
DISTTARGZ=../cricket-$(VER).tar.gz

# for safety, do nothing if no argument is given to make...
all:
	@echo "This Makefile is only used by the maintainers. Please"
	@echo "read the README and doc/beginner.txt files to get"
	@echo "started installing Cricket."

ver:	Makefile
	@echo "Updating VERSION file"
	@$(P4) edit VERSION lib/Common/Version.pm
	@echo "Cricket version $(VER) (" `date` ")" > VERSION
	@echo '$$Common::global::gVersion = "Cricket version $(VER) (' `date` ')";' \
		> lib/Common/Version.pm
	@echo '1;' >> lib/Common/Version.pm

dist: ver
	@echo "Packaging Cricket $(VER) for distribution"
	@( 	rm -f $(DISTTARGZ)	;\
		mkdir $(DISTDIR)	;\
		tar cf - `p4 files ... | grep -v ' delete ' | \
			sed -e 's/\/\/depot\/operations\/nsgtools\/cricket\///;' | \
			sed -e 's/#.*//'` | (cd $(DISTDIR); tar xf -)	;\
		find $(DISTDIR) -exec chmod +w {} \;	;\
		rm -rf $(DISTDIR)/lib/lib 	;\
		rm -rf $(DISTDIR)/lib/sun4-solaris	;\
		rm -f $(DISTDIR)/lib/RRD.pm	;\
		rm -f $(DISTDIR)/lib/ntmake.pl	;\
		( cd .. ; tar cf cricket-$(VER).tar cricket-$(VER) )	;\
		gzip -9 $(DISTTAR)	;\
		rm -rf $(DISTDIR)	;\
	)

scp:
	-scp $(DISTTARGZ) www.munitions.com:.public_html/cricket
