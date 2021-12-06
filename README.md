SPARQL compiler functions  for PostgreSQL
=======================================

This is an extension for PostgreSQL. 

It helps one query SPARQL datasources.
SPARQL queries are compiled into Postgres views, so you can use them nicely in SQL.

It is currently used with Virtuoso, so it is useful with sources like dbpedia.
It might or might not with other RDF backends.

Installation
------------

Install appropriate Perl packages

    apt install libwww-perl libtry-tiny-perl

To build and install this module:

    make
    make install
    make clean install installcheck

or selecting a specific PostgreSQL installation:

    make PG_CONFIG=/some/where/bin/pg_config
    make PG_CONFIG=/some/where/bin/pg_config install
    make PG_CONFIG=/some/where/bin/pg_config installcheck
    make PGPORT=5432 PG_CONFIG=/usr/lib/postgresql/10/bin/pg_config clean install installcheck

Make sure you set the connection parameters like PGPORT right for testing.

And finally inside the database:

    CREATE EXTENSION sparql;

Using
-----

Get data on a particular dbpedia resource:

```sql
SELECT * 
  FROM sparql.get_properties('dbpedia','http://dbpedia.org/resource/Johann_Sebastian_Bach');

SELECT * 
  FROM sparql.get_references('dbpedia','http://dbpedia.org/resource/Johann_Sebastian_Bach');
```

To compile a SPARQL query into SQL function + view:

```sql
SELECT sparql.compile_query(endpoint, identifier, sparql_query[, grouping]);
```

SPARQL endpoint is queried to determine the result format of the specified query.
Then function `identitier()` and view `identifier` are created.
Created function queries any SPARQL endpoint and returns result as SQL table.
Created view is just a convenience layer over created function.
Once created, these can be further tweaked manualy for extra functionality.

Parameters:
+ `endpoint` - default SPARQL endpoint. 
+ `identifier` - SQL identifier of function and view to be created, with or without schema
+ `sparql_query` - SPARQL query to run
+ `grouping` - optional array of identifiers to group by. Grouping is done in a view. When grouping, distinct values of non-grouped columns are aggregated into arrays.

for example:

```sql
SELECT sparql.compile_query('dbpedia','ludwig_van',$$
select ?predicate, ?object
where {
 <http://dbpedia.org/resource/Ludwig_van_Beethoven> ?predicate ?object.
}
$$,'{predicate}');

SELECT * from ludwig_van;
```
