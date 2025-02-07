SET search_path = sparql, pg_catalog;

INSERT INTO endpoint  VALUES ('europeana', 'https://data.europa.eu/sparql');

INSERT INTO namespace VALUES ('results', 'http://www.w3.org/2005/sparql-results#');
UPDATE namespace SET name = 'dbp' WHERE uri = 'http://dbpedia.org/property/';
--INSERT INTO namespace VALUES ('dbp',     'http://dbpedia.org/property/');
--INSERT INTO namespace VALUES ('dbo',     'http://dbpedia.org/ontology/');
INSERT INTO namespace VALUES ('dbr',     'http://dbpedia.org/resource/');


alter function get_properties rename to get_properties0;

CREATE OR REPLACE FUNCTION get_properties(endpoint_name name, iri text, 
OUT predicate text, OUT object text, OUT value text, OUT lang text, OUT datatype text) RETURNS SETOF record
    LANGUAGE plperlu STABLE STRICT ROWS 5000
    AS $_$
use LWP::Simple;
use URI::Escape;
use JSON;

my ($name,$iri)=@_;
unless($iri) { return; }
my $p=spi_prepare('select sparql.endpoint_url($1)','name');
my $baseUrl = spi_exec_prepared($p,$name)->{rows}->[0]->{endpoint_url};
unless($baseUrl) {
  elog(ERROR,'No endpoint definition in sparql.endpoint for name "'.$name.'"');
}

$iri=~s!(\\|>|\n|\r|\t)!{"\t"=>'\t',"\n"=>'\n',"\r"=>'\r','>'=>'\>','\\'=>'\\\\' }->{$1}!ges; 
$iri=qq{<$iri>};
my $query = <<"SPARQL";
prefix rdfs:  <http://www.w3.org/2000/01/rdf-schema#>

select distinct 
 (?p as ?predicate) 
 (?o as ?object)
 (coalesce(?lo, ?o) as ?value)
 (lang(?lo) as ?lang)
 (coalesce(datatype(?lo),datatype(?o)) as ?datatype) 
where {
  $iri ?p ?o.
  OPTIONAL {?o rdfs:label ?lo}.
}
order by ?p
SPARQL

my $url  = $baseUrl."?debug=on&timeout=&save=display&fname=&format=application%2Fsparql-results%2Bjson&query=".uri_escape_utf8($query);
my $json = get($url);
my $data = decode_json($json);
my $vars = $data->{head}{vars};
my $bindings = $data->{results}{bindings};
for my $row (@{$bindings}) {
	my $r = {};
	for my $var (@{$vars}) { $r->{$var}=$row->{$var}{value}; }
	return_next $r;
}
return undef;
$_$;

