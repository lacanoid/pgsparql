select *
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
-- select * from bach
;
