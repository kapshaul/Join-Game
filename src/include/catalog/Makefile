#-------------------------------------------------------------------------
#
# Makefile for src/include/catalog
#
# Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/include/catalog/Makefile
#
#-------------------------------------------------------------------------

subdir = src/include/catalog
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

# location of Catalog.pm
catalogdir = $(top_srcdir)/src/backend/catalog

# 'make reformat-dat-files' is a convenience target for rewriting the
# catalog data files in our standard format.  This includes collapsing
# out any entries that are redundant with a BKI_DEFAULT annotation.
reformat-dat-files:
	$(PERL) -I $(catalogdir) $(srcdir)/reformat_dat_file.pl -o $(srcdir) $(srcdir)/pg_*.dat

# 'make expand-dat-files' is a convenience target for expanding out all
# default values in the catalog data files.  This should be run before
# altering or removing any BKI_DEFAULT annotation.
expand-dat-files:
	$(PERL) -I $(catalogdir) $(srcdir)/reformat_dat_file.pl -o $(srcdir) $(srcdir)/pg_*.dat --full-tuples

.PHONY: reformat-dat-files expand-dat-files
