SET search_path = sparql, pg_catalog;

CREATE OR REPLACE FUNCTION sparql.get_references(endpoint_name name, iri text, out subject text, OUT predicate text, out label text,out lang text)
 RETURNS SETOF record
  LANGUAGE plperlu
   STABLE STRICT ROWS 5000
   AS $function$
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
prefix rdf:   <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
prefix vc:    <http://www.w3.org/2006/vcard/ns#>
prefix swivt: <http://semantic-mediawiki.org/swivt/1.0#>
prefix dc:    <http://purl.org/dc/elements/1.1/>
prefix foaf:  <http://xmlns.com/foaf/0.1/>

select distinct
 (coalesce(?ls, ?s) as ?subject),
 (?p as ?predicate),
 (?l as ?label),
 (lang(?ls) as ?lang)
 where {
  ?s ?p $iri.
  OPTIONAL {?p rdfs:label ?l}.
  OPTIONAL {?s rdfs:label ?ls}.
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
$function$
;

COMMENT ON FUNCTION get_references(endpoint_name name, iri text)
 IS 'Get properties for RDF resource from SPARQL endpoint';

INSERT INTO namespace VALUES ('schema', 'http://schema.org/');
