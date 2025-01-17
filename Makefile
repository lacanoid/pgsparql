PG_CONFIG = pg_config
PKG_CONFIG = pkg-config

extension_version = 1.0

EXTENSION = sparql
PGFILEDESC = "sparql - SPARQL compiler"

DATA = $(EXTENSION)--0.3.sql $(EXTENSION)--0.3--0.4.sql 
DATA_built = $(EXTENSION)--$(extension_version).sql

REGRESS = init base sparql
REGRESS_OPTS = --inputdir=test

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(extension_version).sql: $(EXTENSION).sql
	cat $^ >$@

testall.sh:
	pg_lsclusters -h | perl -ne '@_=split("\\s+",$$_); print "make PGPORT=$$_[2] PG_CONFIG=/usr/lib/postgresql/$$_[0]/bin/pg_config clean install installcheck\n";' > testall.sh

build: testall.sh
build:
	tail -1 testall.sh | sh

