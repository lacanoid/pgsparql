Changelog
=========

version 1.0
- added 'results' and 'dbr' namespaces
- namespace 'dbpedia' renamed to 'dbp'
- removed `label` column from `get_properties()`
- improved tests
- removed .travis.yml

version 0.4
- added get_references() function
- removed dependancy on DateTime perl module in compile_query()
- iri_crunch() function added to convert predicates into readable form
- added 'schema' [http://schema.org/]  namespace
- added openarchives.org namespaces 'oai','ore','oai_dc' 
- added other wanted namespaces: 'xsi', 'dcat'
- added .travis.yml

version 0.3
- get_properties() function improvements
- list_properties() now lists all properies from an endpoint
- iri_ns() function added

version 0.2
- remove nulls from groupings
- improved tests

version 0.1
- initial import
