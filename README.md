SPARQL compiler functions  for PostgreSQL
=======================================

This is an extension for PostgreSQL.

Installation
------------

To build and install this module:

    make
    make install

or selecting a specific PostgreSQL installation:

    make PG_CONFIG=/some/where/bin/pg_config
    make PG_CONFIG=/some/where/bin/pg_config install

And finally inside the database:

    CREATE EXTENSION sparql;

Using
-----

