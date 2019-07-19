# Makefile for Sphinx documentation

# You can set these variables from the command line.
SPHINXOPTS    =
SPHINXBUILD   = sphinx-build
SPHINXPROJ    = BDETools
SOURCEDIR     = docs
BUILDDIR      = build

# Put it first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

.PHONY: help Makefile

internal: Makefile
	@mkdir -p $(BUILDDIR)/$@/src
	@rm -rf $(BUILDDIR)/$@/src/*
	# Copy markdown source into modification area
	@cp -r docs/* $(BUILDDIR)/$@/src/
	# Remove the {{{ internal }}} markers, but keep the text between them   
	@find  $(BUILDDIR)/$@/src/ -iname "*.rst" -exec sed  -i '/{{{[[:space:]]*internal/{:a;N;/}}}/!ba;s/{{{[[:space:]]*internal[[:space:]]*\n\(.*\)\n}}}/\1/;p;d}' {} \;
	# Remove the {{{ oss }} markers and the text between them
	@find  $(BUILDDIR)/$@/src/ -iname "*.rst" -exec sed -i '/{{{[[:space:]]*oss/,/}}}/d' {} \;
	# Starting Sphinx build...
	@$(SPHINXBUILD) -M html "$(BUILDDIR)/$@/src" "$(BUILDDIR)/$@/" -t internal $(SPHINXOPTS) $(O)

oss: Makefile
	@mkdir -p $(BUILDDIR)/$@/src
	@rm -rf $(BUILDDIR)/$@/src/*
	# Copy markdown source into modification area
	@cp -r docs/* $(BUILDDIR)/$@/src/
	# Remove the {{{ oss }}} markers, but keep the text between them   
	@find  $(BUILDDIR)/$@/src/ -iname "*.rst" -exec sed  -i '/{{{[[:space:]]*oss/{:a;N;/}}}/!ba;s/{{{[[:space:]]*oss[[:space:]]*\n\(.*\)\n}}}/\1/;p;d}' {} \;
	# Remove the {{{ internal }} markers and the text between them
	@find  $(BUILDDIR)/$@/src/ -iname "*.rst" -exec sed -i '/{{{[[:space:]]*internal/,/}}}/d' {} \;
	# Starting Sphinx build...
	@$(SPHINXBUILD) -M html "$(BUILDDIR)/$@/src" "$(BUILDDIR)/$@/" -t oss $(SPHINXOPTS) $(O)

# Catch-all target: route all unknown targets to Sphinx using the new
# "make mode" option.  $(O) is meant as a shortcut for $(SPHINXOPTS).
%: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)


#GH_PAGES_SOURCES = docs Makefile readme.md
#gh-pages:
#	git checkout gh-pages
#	rm -rf * 
#	git checkout master $(GH_PAGES_SOURCES)
#	git reset HEAD
#	make html
#	mv -fv build/html/* ./
#	mv -fv build/html/.nojekyll ./
#	rm -rf $(GH_PAGES_SOURCES) build
#	git add -A
#	-git commit -m "Generated gh-pages for `git log master -1 --pretty=short --abbrev-commit`"
#	-git push origin gh-pages
#	git checkout master
