CREATE EXTENSION plperl;
CREATE EXTENSION plperlu;
CREATE EXTENSION sparql;
\pset tuples_only

\dx sparql

create table ns1 as select name from sparql.namespace;

DROP extension sparql;

CREATE EXTENSION sparql VERSION '0.3';
ALTER EXTENSION sparql update;

\dx sparql

create table ns2 as select name from sparql.namespace;

-- namespaces in clean but not updated version
select name from ns1 where name not in (select name from ns2); 

-- namespaces in updated but not clean version
select name from ns2 where name not in (select name from ns1); 
