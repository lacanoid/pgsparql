SPARQL compiler functions  for PostgreSQL
=======================================

This is an extension for PostgreSQL. 

It helps one query SPARQL datasources.
SPARQL queries are compiled into Postgres views, so you can use them nicely in SQL.

It is currently used with Virtuoso, so it is useful with sources like dbpedia.
It might or might not with other RDF backends.

Installation
------------

To build and install this module:

    make
    make install installcheck

or selecting a specific PostgreSQL installation:

    make PG_CONFIG=/some/where/bin/pg_config
    make PG_CONFIG=/some/where/bin/pg_config install

And finally inside the database:

    CREATE EXTENSION sparql;

Using
-----

Get data on a particular dbpedia resource:

```sql
SELECT * 
  FROM sparql.get_properties('dbpedia','http://dbpedia.org/resource/Johann_Sebastian_Bach')
```
