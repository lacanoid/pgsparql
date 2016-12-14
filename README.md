SPARQL compiler functions  for PostgreSQL
=======================================

This is an extension for PostgreSQL.

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
