select * 
  from sparql.get_properties('dbpedia','http://dbpedia.org/resource/Johann_Sebastian_Bach')
 where predicate='http://dbpedia.org/ontology/birthYear';
