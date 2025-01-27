CREATE EXTENSION plperl;
CREATE EXTENSION plperlu;
CREATE EXTENSION sparql;
\pset tuples_only

\dx sparql

DROP extension sparql;

CREATE EXTENSION sparql VERSION '0.3';
ALTER EXTENSION sparql update;

\dx sparql
