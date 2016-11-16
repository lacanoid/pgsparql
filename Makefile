PG_CONFIG = pg_config
PKG_CONFIG = pkg-config

extension_version = 0.1

EXTENSION = sparql
DATA_built = sparql--$(extension_version).sql

REGRESS = init test
REGRESS_OPTS = --inputdir=test

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

sparql--$(extension_version).sql: sparql.sql
	cat $^ >$@
