select distinct predicate,value
  from sparql.get_properties('dbpedia','http://dbpedia.org/resource/Johann_Sebastian_Bach')
 where predicate = 'http://dbpedia.org/ontology/birthYear'
;
select substr(sparql.compile_query('dbpedia','bach',$$
select ?predicate, ?object
where {
 <http://dbpedia.org/resource/Johann_Sebastian_Bach> ?predicate ?object.
}
$$,'{predicate}'),1,31) as magick
;
select * from bach where predicate='http://dbpedia.org/ontology/birthYear';
;
with q as (
 values 
  ('http://purl.org/dc/elements/1.1/creator'),
  ('http://www.w3.org/2000/10/swap/pim/exif#apperture'),
  ('http://krneki.org/id') 
)
select sparql.iri_ident(column1) as ident,
       sparql.iri_prefix(column1) as prefix,
       sparql.iri_ns(column1) as ns,
       sparql.iri_crunch(column1) as crunch
  from q
;