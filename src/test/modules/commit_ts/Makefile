# src/test/modules/commit_ts/Makefile

REGRESS = commit_timestamp
REGRESS_OPTS = --temp-config=$(top_srcdir)/src/test/modules/commit_ts/commit_ts.conf

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = src/test/modules/commit_ts
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

check: prove-check

prove-check: | temp-install
	$(prove_check)
