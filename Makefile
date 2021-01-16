PG_CONFIG = pg_config
PKG_CONFIG = pkg-config

extension_version = 0.4

EXTENSION = sparql
PGFILEDESC = "sparql - SPARQL compiler"

DATA = $(EXTENSION)--0.3.sql $(EXTENSION)--0.3--0.4.sql 
DATA_built = $(EXTENSION)--$(extension_version).sql

REGRESS = init test
REGRESS_OPTS = --inputdir=test

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(extension_version).sql: $(EXTENSION).sql
	cat $^ >$@

