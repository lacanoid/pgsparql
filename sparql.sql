-- CREATE SCHEMA sparql;

COMMENT ON SCHEMA sparql IS 'Interface to Virtuoso SPARQL endpoint';

SET search_path = sparql, pg_catalog;

--
-- Name: iri; Type: DOMAIN; Schema: sparql; Owner: sparql
--

CREATE DOMAIN iri AS text;

--
-- Name: config; Type: TABLE; Schema: sparql; Owner: sparql; Tablespace: 
--

CREATE TABLE IF NOT EXISTS config (
    name text NOT NULL,
    value text,
    regtype regtype DEFAULT 'text'::regtype NOT NULL,
    comment text
);

--
-- Name: TABLE config; Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON TABLE config IS 'Various configuration options';

--
-- Name: endpoint; Type: TABLE; Schema: sparql; Owner: sparql; Tablespace: 
--

CREATE TABLE IF NOT EXISTS endpoint (
    name name NOT NULL,
    url text NOT NULL
);

--
-- Name: TABLE endpoint; Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON TABLE endpoint IS 'SPARQL endpoint definitions';


--
-- Name: namespace; Type: TABLE; Schema: sparql; Owner: sparql; Tablespace: 
--

CREATE TABLE IF NOT EXISTS namespace (
    name text NOT NULL,
    uri iri NOT NULL
);

--
-- Name: TABLE namespace; Type: COMMENT; Schema: sparql; Owner: sparql
--

ALTER TABLE ONLY namespace ADD PRIMARY KEY (name);
ALTER TABLE ONLY namespace ADD UNIQUE (uri);
COMMENT ON TABLE namespace IS 'Table of common RDF namespaces';



--
-- Name: compile_query(name, text, text, name[]); Type: FUNCTION; Schema: sparql; Owner: ziga
--

CREATE OR REPLACE FUNCTION compile_query(endpoint_name name, identifier text, query text, group_by name[] DEFAULT NULL::name[]) RETURNS text
    LANGUAGE plperlu
    AS $_X$
my ($name,$func,$query,$group_by)=@_;
use LWP::Simple;
use URI::Escape;
use DateTime;
use JSON;

my $now = DateTime->now()->iso8601().'Z';
my $p=spi_prepare('select sparql.endpoint_url($1)','name');
my $baseUrl = spi_exec_prepared($p,$name)->{rows}->[0];
unless($baseUrl) {
  elog(ERROR,'No endpoint definition in sparql.endpoint for name "'.$name.'"');
}
$baseUrl = $baseUrl->{endpoint_url};
my $extras ="?debug=on&timeout=&save=display&fname=".
	    "&format=".uri_escape("application/sparql-results+json").
	    "&query=";

my $url = $baseUrl.$extras;
my $json = get($url.uri_escape($query));
my $data;
eval { $data = decode_json($json); } 
  or do { elog(ERROR,'SPARQL error'.$json); };
my $vars = $data->{head}{vars};
if(!ref($vars)) { elog(ERROR,'bad result'); }
my $outputs = join(', ', map { qq{out "$_" text} } @{$vars});
my $bindings = $data->{results}{bindings};
$query=~s/^\s*//; $query=~s/\s*$//;

my $ddl1 = "create or replace function $func(endpoint_name name default '$name',$outputs) \nreturns setof record \nas ".'$sparql$'.'
use LWP::Simple;
use URI::Escape;
use Try::Tiny;
use JSON;

my ($name) = @_;
my $p = spi_prepare(\'select sparql.endpoint_url($1)\',\'name\');
my $endpoint_url = spi_exec_prepared($p,$name)->{rows}->[0]->{endpoint_url};
unless($endpoint_url) {
  elog(ERROR,\'No endpoint definition in sparql.endpoint for name "\'.$name.\'"\');
}
my $extras="?debug=on&timeout=&save=display&fname=".
	   "&format=".uri_escape("application/sparql-results+json").
	   "&query=";
	   
my $query = <<"SPARQL";
'.$query.'
SPARQL

my $url  = $endpoint_url.$extras.uri_escape_utf8($query);
my $json = get($url); 
# $json=~s!\\U([0-9A-F]+)!chr(hex($1))!ge;
try { my $data = decode_json($json);
  my $vars = $data->{head}{vars};
  my $bindings = $data->{results}{bindings};
  for my $row (@{$bindings}) {
	my $r = {};
	for my $var (@{$vars}) { $r->{$var}=$row->{$var}{value}; }
	return_next $r;
  }
  return undef;
} catch {
  elog(ERROR,"SPARQL ENDPOINT FAILURE\n$_");
}
'.'$sparql$'." language plperlu cost 5000;
comment on function $func(name) is 'Compiled with sparql.compile_query() at $now';
";

my @a = (); my @g = (); my $gb = "";
if($group_by) {
	for my $w1 (@$vars) {
	  if( grep {$w1 eq $_} @$group_by ) { push @a,qq{"$w1"}; push @g,$w1; } 
	  else { push @a,qq{array_agg(distinct "$w1") filter (where "$w1" is not null) as "$w1"}; }
    }
    if(@g) { $gb = " group by ".join(', ', map {qq{"$_"}} @g); }
} else { @a = ('*'); }

my $ddl2 = "
create or replace view ${func} as select ".join(', ',@a)." from $func()$gb;
comment on view ${func} is 'Compiled with sparql.compile_query() at $now';
";

my $ddl = $ddl1.$ddl2;
spi_exec_query($ddl,1);
return  $ddl;

$_X$;

COMMENT ON FUNCTION compile_query(name,text,text,name[])
IS 'Compile SPARQL query into a SQL function+view';

--
-- Name: config(text); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE OR REPLACE FUNCTION config(var text) RETURNS text
    LANGUAGE sql
    AS $_$
select "value" from sparql.config where "name"=$1;
$_$;

--
-- Name: FUNCTION config(var text); Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON FUNCTION config(var text) IS 'Return configuration setting';

--
-- Name: endpoint_url(name); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE OR REPLACE FUNCTION endpoint_url(endpoint_name name) RETURNS text
    LANGUAGE sql
    AS $_$
select url from sparql.endpoint where name = $1
$_$;

--
-- Name: FUNCTION endpoint_url(endpoint_name name); Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON FUNCTION endpoint_url(endpoint_name name) IS 'Return SPARQL endpoint url for named endpoint';


--
-- Name: get_properties(name, text); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE OR REPLACE FUNCTION get_properties(endpoint_name name, iri text, 
OUT predicate text, OUT label text, OUT object text, OUT value text, OUT lang text, OUT datatype text) RETURNS SETOF record
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
prefix rdf:   <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
prefix vc:    <http://www.w3.org/2006/vcard/ns#>
prefix swivt: <http://semantic-mediawiki.org/swivt/1.0#>
prefix dc:    <http://purl.org/dc/elements/1.1/>
prefix foaf:  <http://xmlns.com/foaf/0.1/>

select distinct 
 (?p as ?predicate) 
 (?l as ?label) 
 (?o as ?object)
 (coalesce(?lo, ?o) as ?value)
 (lang(?lo) as ?lang)
 (coalesce(datatype(?lo),datatype(?o)) as ?datatype) 
where {
  $iri ?p ?o.
  OPTIONAL {?p rdfs:label ?l}.
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

--
-- Name: FUNCTION get_properties(endpoint_name name, iri text, OUT predicate text, OUT object text, OUT value text, OUT lang text); Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON FUNCTION get_properties(endpoint_name name, iri text)
 IS 'Get properties for RDF resource from SPARQL endpoint';


-- IRI functions

CREATE OR REPLACE FUNCTION iri_ident(text) RETURNS text
    LANGUAGE plperl IMMUTABLE
    AS $_$
  my ($url)=@_;
  if($url=~s!([/#])([_\-a-zA-Z0-9]+)$!$1!) { return $2; }
  return undef;
$_$;
COMMENT ON FUNCTION iri_ident(text) IS 'Get identifier part of IRI';

CREATE OR REPLACE FUNCTION iri_prefix(text) RETURNS text
    LANGUAGE plperl IMMUTABLE
    AS $_$
  my ($url)=@_;
  if($url=~s!([/#])([_\-a-zA-Z0-9]+)$!$1!) { return $url; }
  return undef;
$_$;
COMMENT ON FUNCTION iri_prefix(text) IS 'Get namespace prefix part of IRI';

CREATE OR REPLACE FUNCTION iri_ns(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
 select name from sparql.namespace where uri = sparql.iri_prefix($1)
$_$;
COMMENT ON FUNCTION iri_ns(text) IS 'Get abbreviated namespace for IRI';

--
-- Name: properties(name); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE OR REPLACE FUNCTION list_properties(endpoint_name name, OUT pred text, OUT label text, OUT comment text, OUT cardinality text, OUT range text, OUT "isDefinedBy" text) RETURNS SETOF record
    LANGUAGE plperlu COST 10000
    AS $_X$
use LWP::Simple;
use URI::Escape;
use Try::Tiny;
use JSON;

my ($name) = @_;
my $p = spi_prepare('select sparql.endpoint_url($1)','name');
my $endpoint_url = spi_exec_prepared($p,$name)->{rows}->[0]->{endpoint_url};
unless($endpoint_url) {
  elog(ERROR,'No endpoint definition in sparql.endpoint for name "'.$name.'"');
}
my $extras="?debug=on&timeout=&save=display&fname=".
	   "&format=".uri_escape("application/sparql-results+json").
	   "&query=";
	   
my $query = <<"SPARQL";
select distinct ?pred, ?label, ?comment, ?cardinality, ?range, ?isDefinedBy
WHERE {
  ?pred a rdf:Property.
  ?pred rdfs:label ?label.
  optional {?pred rdfs:comment ?comment}.
  optional {?pred rdfs:range ?range}.
  optional {?pred rdfs:cardinality ?cardinality}.
  optional {?pred rdfs:isDefinedBy ?isDefinedBy}.
}
SPARQL

my $url  = $endpoint_url.$extras.uri_escape_utf8($query);
my $json = get($url); 
# $json=~s!\U([0-9A-F]+)!chr(hex($1))!ge;
try { my $data = decode_json($json);
  my $vars = $data->{head}{vars};
  my $bindings = $data->{results}{bindings};
  for my $row (@{$bindings}) {
	my $r = {};
	for my $var (@{$vars}) { $r->{$var}=$row->{$var}{value}; }
	return_next $r;
  }
  return undef;
} catch {
  elog(ERROR,"SPARQL ENDPOINT FAILURE\n$_");
}
$_X$;

--
-- Name: FUNCTION properties(endpoint_name name, OUT pred text, OUT label text, OUT comment text, OUT cardinality text, OUT range text, OUT "isDefinedBy" text); Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON FUNCTION list_properties(endpoint_name name)
IS 'Get a list of all properties from a SPARQL endpoint';

SET default_with_oids = false;

--
-- Data for Name: endpoint; Type: TABLE DATA; Schema: sparql; Owner: sparql
--

INSERT INTO endpoint VALUES ('localhost', 'http://localhost:8890/sparql/');
INSERT INTO endpoint VALUES ('virtuoso',  'http://localhost:8890/sparql/');
INSERT INTO endpoint VALUES ('dbpedia',   'http://dbpedia.org/sparql/');
INSERT INTO endpoint VALUES ('geonames',  'http://www.lotico.com:3030/lotico/sparql');
INSERT INTO endpoint VALUES ('wikidata',  'https://query.wikidata.org/sparql');

--
-- Data for Name: namespace; Type: TABLE DATA; Schema: sparql; Owner: sparql
--

INSERT INTO namespace VALUES ('NC', 'http://home.netscape.com/NC-rdf#');
INSERT INTO namespace VALUES ('NS0', 'http://www.daml.org/2002/02/telephone/1/areacodes-ont#');
INSERT INTO namespace VALUES ('a1', 'http://protege.stanford.edu/system#');
INSERT INTO namespace VALUES ('a2', 'http://www.cogsci.princeton.edu/~wn/concept#');
INSERT INTO namespace VALUES ('admin', 'http://webns.net/mvcb/');
INSERT INTO namespace VALUES ('ag', 'http://purl.org/rss/1.0/modules/aggregation/');
INSERT INTO namespace VALUES ('air', 'http://www.megginson.com/exp/ns/airports#');
INSERT INTO namespace VALUES ('ajft', 'http://ajft.org/foaf.rdf#');
INSERT INTO namespace VALUES ('an2', 'http://rdf.desire.org/vocab/recommend.rdf#');
INSERT INTO namespace VALUES ('annotate', 'http://purl.org/rss/1.0/modules/annotate/');
INSERT INTO namespace VALUES ('app', 'http://example.com/app#');
INSERT INTO namespace VALUES ('assert', 'http://ebiquity.umbc.edu/ontology/assertion.owl#');
INSERT INTO namespace VALUES ('assoc', 'http://ebiquity.umbc.edu/ontology/association.owl#');
INSERT INTO namespace VALUES ('at', 'http://www.sixapart.com/ns/at');
INSERT INTO namespace VALUES ('attribute', 'http://wiki.ontoworld.org/index.php/_Attribute-3A');
INSERT INTO namespace VALUES ('b', 'http://www.cogsci.princeton.edu/~wn/schema/');
INSERT INTO namespace VALUES ('base', 'http://www.aktors.org/ontology/base#');
INSERT INTO namespace VALUES ('bbc', 'http://bbc.co.uk/ns#');
INSERT INTO namespace VALUES ('bio', 'http://purl.org/vocab/bio/0.1/');
INSERT INTO namespace VALUES ('bk', 'http://www.hackcraft.net/bookrdf/vocab/0_1/');
INSERT INTO namespace VALUES ('blogChannel', 'http://backend.userland.com/blogChannelModule');
INSERT INTO namespace VALUES ('bulkfeeds', 'http://bulkfeeds.net/xmlns#');
INSERT INTO namespace VALUES ('bz', 'http://bitzi.com/xmlns/2002/01/bz-core#');
INSERT INTO namespace VALUES ('canon', 'http://nwalsh.com/rdf/exif-canon#');
INSERT INTO namespace VALUES ('cap', 'http://impressive.net/people/gerald/2001/captivate-ns#');
INSERT INTO namespace VALUES ('card', 'http://person.org/BusinessCard/');
INSERT INTO namespace VALUES ('cc', 'http://web.resource.org/cc/');
INSERT INTO namespace VALUES ('ccpp', 'http://www.w3.org/2000/07/04-ccpp#');
INSERT INTO namespace VALUES ('ccpp2', 'http://www.w3.org/2002/11/08-ccpp-schema#');
INSERT INTO namespace VALUES ('chefmoz', 'http://chefmoz.org/rdf/elements/1.0/');
INSERT INTO namespace VALUES ('chrome', 'http://www.mozilla.org/rdf/chrome#');
INSERT INTO namespace VALUES ('cld', 'http://www.ukoln.ac.uk/metadata/rslp/1.0/');
INSERT INTO namespace VALUES ('clique', 'http://russell.rucus.net/2004/clique/#');
INSERT INTO namespace VALUES ('cmet', 'http://veggente.berlios.de/ns/RIM_CMET#');
INSERT INTO namespace VALUES ('co', 'http://purl.org/rss/1.0/modules/company/');
INSERT INTO namespace VALUES ('conf', 'http://www.mindswap.org/2004/www04photo.owl#');
INSERT INTO namespace VALUES ('confoto', 'http://www.confoto.org/ns/confoto#');
INSERT INTO namespace VALUES ('contact2', 'http://ebiquity.umbc.edu/ontology/contact.owl#');
INSERT INTO namespace VALUES ('content', 'http://purl.org/rss/1.0/modules/content/');
INSERT INTO namespace VALUES ('cvs', 'http://nwalsh.com/rdf/cvs#');
INSERT INTO namespace VALUES ('cyc', 'http://opencyc.sourceforge.net/daml/cyc.daml#');
INSERT INTO namespace VALUES ('daml2', 'http://www.daml.org/2000/10/daml-ont#');
INSERT INTO namespace VALUES ('date', 'java:java.util.Date');
INSERT INTO namespace VALUES ('dc10', 'http://purl.org/dc/elements/1.0/');
INSERT INTO namespace VALUES ('dc', 'http://purl.org/dc/elements/1.1/');
INSERT INTO namespace VALUES ('dcq1', 'http://dublincore.org/2000/03/13/dcq#');
INSERT INTO namespace VALUES ('dcq', 'http://purl.org/dc/qualifiers/1.0/');
INSERT INTO namespace VALUES ('dct', 'http://dublincore.org/2000/03/13-dctype');
INSERT INTO namespace VALUES ('dcterms', 'http://purl.org/dc/terms/');
INSERT INTO namespace VALUES ('dctype1', 'http://dublincore.org/2003/12/08/dctype#');
INSERT INTO namespace VALUES ('dctype', 'http://purl.org/dc/dcmitype/');
INSERT INTO namespace VALUES ('doap2', 'http://usefulinc.com/ns/doap/#');
INSERT INTO namespace VALUES ('doc', 'http://www.w3.org/2000/10/swap/pim/doc#');
INSERT INTO namespace VALUES ('e', 'http://eulersharp.sourceforge.net/2003/03swap/log-rules#');
INSERT INTO namespace VALUES ('ecademy', 'http://www.ecademy.com/namespace/');
INSERT INTO namespace VALUES ('eg', 'http://example.org/');
INSERT INTO namespace VALUES ('enc', 'http://purl.oclc.org/net/rss_2.0/enc#');
INSERT INTO namespace VALUES ('ent', 'http://jena.hpl.hp.com/ENT/1.0/#');
INSERT INTO namespace VALUES ('eor', 'http://dublincore.org/2000/03/13/eor#');
INSERT INTO namespace VALUES ('ese', 'http://www.europeana.eu/schemas/ese/');
INSERT INTO namespace VALUES ('ethan', 'http://spire.umbc.edu/ontologies/ethan.owl#');
INSERT INTO namespace VALUES ('ev', 'http://purl.org/rss/1.0/modules/event/');
INSERT INTO namespace VALUES ('event', 'http://ebiquity.umbc.edu/ontology/event.owl#');
INSERT INTO namespace VALUES ('ex1', 'http://example.org/stuff/1.0/');
INSERT INTO namespace VALUES ('ex', 'http://www.example.com/schema#');
INSERT INTO namespace VALUES ('exif4', 'http://impressive.net/people/gerald/2001/exif#');
INSERT INTO namespace VALUES ('exif3', 'http://nwalsh.com/rdf/exif#');
INSERT INTO namespace VALUES ('exif2', 'http://www.kanzaki.com/ns/exif#');
INSERT INTO namespace VALUES ('exifgps', 'http://nwalsh.com/rdf/exif-gps#');
INSERT INTO namespace VALUES ('exifi', 'http://nwalsh.com/rdf/exif-intrinsic#');
INSERT INTO namespace VALUES ('feedburner', 'http://rssnamespace.org/feedburner/ext/1.0');
INSERT INTO namespace VALUES ('file', 'http://www.w3.org/2000/10/swap/pim/file#');
INSERT INTO namespace VALUES ('flair', 'http://simile.mit.edu/2005/04/flair#');
INSERT INTO namespace VALUES ('fotonotes', 'http://fotonotes.net/rdf/fotonotes-schema#');
INSERT INTO namespace VALUES ('g', 'http://www.w3.org/2001/02pd/gv#');
INSERT INTO namespace VALUES ('gal', 'http://norman.walsh.name/rdf/gallery#');
INSERT INTO namespace VALUES ('geoinsee', 'http://rdf.insee.fr/geo/');
INSERT INTO namespace VALUES ('geo', 'http://www.w3.org/2003/01/geo/wgs84_pos#');
INSERT INTO namespace VALUES ('gps', 'http://hackdiary.com/ns/gps#');
INSERT INTO namespace VALUES ('gump', 'http://gump.apache.org/schemas/main/1.0/');
INSERT INTO namespace VALUES ('hl7', 'urn:hl7-org:v3/mif');
INSERT INTO namespace VALUES ('http', 'http://www.w3.org/1999/xx/http#');
INSERT INTO namespace VALUES ('iX', 'http://ns.adobe.com/iX/1.0/');
INSERT INTO namespace VALUES ('ical1', 'http://www.w3.org/2002/12/cal/#');
INSERT INTO namespace VALUES ('image', 'http://jibbering.com/vocabs/image/#');
INSERT INTO namespace VALUES ('img1', 'http://igargoyle.com/rss/1.0/modules/img/');
INSERT INTO namespace VALUES ('img2', 'http://jibbering.com/2002/3/svg/#');
INSERT INTO namespace VALUES ('imreg', 'http://www.w3.org/2004/02/image-regions#');
INSERT INTO namespace VALUES ('iw', 'http://inferenceweb.stanford.edu/2004/07/iw.owl#');
INSERT INTO namespace VALUES ('iwip', 'http://www.iwi-iuk.org/material/RDF/Schema/Property/iwip#');
INSERT INTO namespace VALUES ('jms', 'http://jena.hpl.hp.com/2003/08/jms#');
INSERT INTO namespace VALUES ('jpegrdf', 'http://nwalsh.com/rdf/jpegrdf#');
INSERT INTO namespace VALUES ('keyword', 'http://animaldiversity.ummz.umich.edu/local/keywords/keywords.owl#');
INSERT INTO namespace VALUES ('ethan_kw', 'http://spire.umbc.edu/ontologies/ethan_keywords.owl#');
INSERT INTO namespace VALUES ('l', 'http://purl.org/rss/1.0/modules/link/');
INSERT INTO namespace VALUES ('lang', 'http://purl.org/net/inkel/rdf/schemas/lang/1.1#');
INSERT INTO namespace VALUES ('marc', 'http://www.loc.gov/marc/relators/');
INSERT INTO namespace VALUES ('mat', 'http://www.w3.org/2002/05/matrix/vocab#');
INSERT INTO namespace VALUES ('math', 'http://www.w3.org/2000/10/swap/math#');
INSERT INTO namespace VALUES ('mathind', 'http://www.math.org/#');
INSERT INTO namespace VALUES ('mcc', 'http://mutemap.openmute.org/2003/mcc#');
INSERT INTO namespace VALUES ('mesh', 'http://www.nlm.nih.gov/mesh/2004#');
INSERT INTO namespace VALUES ('mindswap', 'http://www.mindswap.org/2003/owl/mindswap#');
INSERT INTO namespace VALUES ('mindswap-projects', 'http://www.mindswap.org/2004/owl/mindswap-projects#');
INSERT INTO namespace VALUES ('mindswappers', 'http://www.mindswap.org/2004/owl/mindswappers#');
INSERT INTO namespace VALUES ('mm20', 'http://musicbrainz.org/mm/mm-2.0#');
INSERT INTO namespace VALUES ('mm21', 'http://musicbrainz.org/mm/mm-2.1#');
INSERT INTO namespace VALUES ('mms', 'http://www.openmobilealliance.org/tech/profiles/MMS/ccppschema-20050301-MMS1.2#');
INSERT INTO namespace VALUES ('mmswap', 'http://www.wapforum.org/profiles/MMS/ccppschema-20010111#');
INSERT INTO namespace VALUES ('mnp', 'http://www.iwi-iuk.org/material/RDF/1.1/Schema/Property/mnp#');
INSERT INTO namespace VALUES ('mnst', 'http://www.iwi-iuk.org/material/RDF/1.1/descriptor/#');
INSERT INTO namespace VALUES ('moblog', 'http://kaywa.com/rss/modules/moblog/');
INSERT INTO namespace VALUES ('modwiki', 'http://www.usemod.com/cgi-bin/mb.pl?ModWiki');
INSERT INTO namespace VALUES ('mp', 'http://www.mutopiaproject.org/piece-data/0.1/');
INSERT INTO namespace VALUES ('mu', 'http://storymill.com/mu/2005/03/');
INSERT INTO namespace VALUES ('neg', 'http://www.inrialpes.fr/opera/people/Tayeb.Lemlouma/NegotiationSchema/ClientProfileSchema-03012002#');
INSERT INTO namespace VALUES ('news', 'http://www.nature.com/schema/2004/05/news#');
INSERT INTO namespace VALUES ('nhet', 'http://spire.umbc.edu/ontologies/nhet.owl#');
INSERT INTO namespace VALUES ('nikon', 'http://nwalsh.com/rdf/exif-nikon5700#');
INSERT INTO namespace VALUES ('nikon950', 'http://nwalsh.com/rdf/exif-nikon950#');
INSERT INTO namespace VALUES ('nines', 'http://www.nines.org/schema#');
INSERT INTO namespace VALUES ('nlo', 'http://nulllogicone.net/schema.rdfs#');
INSERT INTO namespace VALUES ('nwn-what', 'http://norman.walsh.name/knows/what#');
INSERT INTO namespace VALUES ('nwn-where', 'http://norman.walsh.name/knows/where#');
INSERT INTO namespace VALUES ('nwn-who', 'http://norman.walsh.name/knows/who#');
INSERT INTO namespace VALUES ('oiled', 'http://img.cs.man.ac.uk/oil/oiled#');
INSERT INTO namespace VALUES ('ontosem', 'http://morpheus.cs.umbc.edu/aks1/ontosem.owl#');
INSERT INTO namespace VALUES ('ontoware', 'http://swrc.ontoware.org/ontology/ontoware#');
INSERT INTO namespace VALUES ('org', 'http://www.w3.org/2001/04/roadmap/org#');
INSERT INTO namespace VALUES ('os', 'http://downlode.org/rdf/os/0.1/');
INSERT INTO namespace VALUES ('owl', 'http://www.w3.org/2002/07/owl#');
INSERT INTO namespace VALUES ('p', 'http://www.usefulinc.com/picdiary/');
INSERT INTO namespace VALUES ('p0', 'http://eulersharp.sourceforge.net/2003/03swap/xsd-rules#');
INSERT INTO namespace VALUES ('p1', 'http://eulersharp.sourceforge.net/2003/03swap/rdfs-rules#');
INSERT INTO namespace VALUES ('person', 'http://ebiquity.umbc.edu/ontology/person.owl#');
INSERT INTO namespace VALUES ('pm', 'http://mindswap.org/2005/owl/photomesa#');
INSERT INTO namespace VALUES ('prf', 'http://www.openmobilealliance.org/tech/profiles/UAPROF/ccppschema-20021212#');
INSERT INTO namespace VALUES ('prfwap', 'http://www.wapforum.org/profiles/UAPROF/ccppschema-20010430#');
INSERT INTO namespace VALUES ('prism', 'http://prismstandard.org/namespaces/1.2/basic/');
INSERT INTO namespace VALUES ('process10', 'http://www.daml.org/services/owl-s/1.0/Process.owl#');
INSERT INTO namespace VALUES ('process11', 'http://www.daml.org/services/owl-s/1.1/Process.owl#');
INSERT INTO namespace VALUES ('profile', 'http://www.daml.org/services/owl-s/1.0/Profile.owl#');
INSERT INTO namespace VALUES ('project', 'http://ebiquity.umbc.edu/ontology/project.owl#');
INSERT INTO namespace VALUES ('project2', 'http://www.mindswap.org/2003/owl/project#');
INSERT INTO namespace VALUES ('protege', 'http://protege.stanford.edu/plugins/owl/protege#');
INSERT INTO namespace VALUES ('pub', 'http://ebiquity.umbc.edu/ontology/publication.owl#');
INSERT INTO namespace VALUES ('q', 'http://www.w3.org/2004/ql#');
INSERT INTO namespace VALUES ('ra', 'http://www.rossettiarchive.org/schema#');
INSERT INTO namespace VALUES ('random', 'http://random.ioctl.org/#');
INSERT INTO namespace VALUES ('rcs', 'http://www.w3.org/2001/03swell/rcs#');
INSERT INTO namespace VALUES ('rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#');
INSERT INTO namespace VALUES ('rdfs', 'http://www.w3.org/2000/01/rdf-schema#');
INSERT INTO namespace VALUES ('rec', 'http://www.w3.org/2001/02pd/rec54#');
INSERT INTO namespace VALUES ('ref', 'http://purl.org/rss/1.0/modules/reference/');
INSERT INTO namespace VALUES ('rel', 'http://purl.org/vocab/relationship/');
INSERT INTO namespace VALUES ('relation', 'http://wiki.ontoworld.org/index.php/_Relation-3A');
INSERT INTO namespace VALUES ('research', 'http://ebiquity.umbc.edu/ontology/research.owl#');
INSERT INTO namespace VALUES ('rim_dt', 'http://veggente.berlios.de/ns/RIMDatatype#');
INSERT INTO namespace VALUES ('role', 'http://www.loc.gov/loc.terms/relators/');
INSERT INTO namespace VALUES ('rs', 'http://www.w3.org/2001/sw/DataAccess/tests/result-set#');
INSERT INTO namespace VALUES ('rss2', 'http://backend.userland.com/RSS2#');
INSERT INTO namespace VALUES ('rss1', 'http://purl.org/rss/1.0/');
INSERT INTO namespace VALUES ('s', 'http://snipsnap.org/rdf/snip-schema#');
INSERT INTO namespace VALUES ('schemaweb', 'http://www.schemaweb.info/schemas/meta/rdf/');
INSERT INTO namespace VALUES ('s0', 'http://www.w3.org/2000/PhotoRDF/dc-1-0#');
INSERT INTO namespace VALUES ('s1', 'http://sophia.inria.fr/~enerbonn/rdfpiclang#');
INSERT INTO namespace VALUES ('se', 'http://www.w3.org/2004/02/skos/extensions#');
INSERT INTO namespace VALUES ('semblog', 'http://www.semblog.org/ns/semblog/0.1/');
INSERT INTO namespace VALUES ('service', 'http://www.daml.org/services/owl-s/1.0/Service.owl#');
INSERT INTO namespace VALUES ('signage', 'http://www.aktors.org/ontology/signage#');
INSERT INTO namespace VALUES ('skos', 'http://www.w3.org/2004/02/skos/core#');
INSERT INTO namespace VALUES ('slash', 'http://purl.org/rss/1.0/modules/slash/');
INSERT INTO namespace VALUES ('smw', 'http://smw.ontoware.org/2005/smw#');
INSERT INTO namespace VALUES ('space', 'http://frot.org/space/0.1/');
INSERT INTO namespace VALUES ('spi', 'http://www.trustix.net/schema/rdf/spi-0.0.1#');
INSERT INTO namespace VALUES ('str', 'http://www.w3.org/2000/10/swap/string#');
INSERT INTO namespace VALUES ('support', 'http://www.aktors.org/ontology/support#');
INSERT INTO namespace VALUES ('svgr', 'http://www.w3.org/2001/svgRdf/axsvg-schema.rdf#');
INSERT INTO namespace VALUES ('swrl', 'http://www.w3.org/2003/11/swrl#');
INSERT INTO namespace VALUES ('sy', 'http://purl.org/rss/1.0/modules/syndication/');
INSERT INTO namespace VALUES ('sy0', 'http://purl.org/rss/modules/syndication/');
INSERT INTO namespace VALUES ('tax', 'http://semweb.mcdonaldbradley.com/OWL/TaxonomyMapping/Definitions/TaxonomySupport.owl#');
INSERT INTO namespace VALUES ('taxo', 'http://purl.org/rss/1.0/modules/taxonomy/');
INSERT INTO namespace VALUES ('template', 'http://redfoot.net/2005/template#');
INSERT INTO namespace VALUES ('terms', 'http://jibbering.com/2002/6/terms#');
INSERT INTO namespace VALUES ('thes', 'http://reports.eea.eu.int/EEAIndexTerms/ThesaurusSchema.rdf#');
INSERT INTO namespace VALUES ('thing', 'http://wiki.ontoworld.org/index.php/_');
INSERT INTO namespace VALUES ('ti', 'http://purl.org/rss/1.0/modules/textinput/');
INSERT INTO namespace VALUES ('tif', 'http://www.limber.rl.ac.uk/External/thesaurus-iso.rdf#');
INSERT INTO namespace VALUES ('trackback', 'http://madskills.com/public/xml/rss/module/trackback/');
INSERT INTO namespace VALUES ('trust', 'http://trust.mindswap.org/ont/trust.owl#');
INSERT INTO namespace VALUES ('units', 'http://visus.mit.edu/fontomri/0.01/units.owl#');
INSERT INTO namespace VALUES ('ure', 'http://medea.mpiwg-berlin.mpg.de/ure/vocab#');
INSERT INTO namespace VALUES ('urfm', 'http://purl.org/urfm/');
INSERT INTO namespace VALUES ('uri', 'http://www.w3.org/2000/07/uri43/uri.xsl?template=');
INSERT INTO namespace VALUES ('vCard', 'http://www.w3.org/2001/vcard-rdf/3.0#');
INSERT INTO namespace VALUES ('vann', 'http://purl.org/vocab/vann/');
INSERT INTO namespace VALUES ('vlma', 'http://medea.mpiwg-berlin.mpg.de/vlma/vocab#');
INSERT INTO namespace VALUES ('vra', 'http://www.swi.psy.uva.nl/mia/vra#');
INSERT INTO namespace VALUES ('vs', 'http://www.w3.org/2003/06/sw-vocab-status/ns#');
INSERT INTO namespace VALUES ('wfw', 'http://wellformedweb.org/CommentAPI/');
INSERT INTO namespace VALUES ('wiki', 'http://purl.org/rss/1.0/modules/wiki/');
INSERT INTO namespace VALUES ('wikiped', 'http://en.wikipedia.org/wiki/');
INSERT INTO namespace VALUES ('wn', 'http://xmlns.com/wordnet/1.6/');
INSERT INTO namespace VALUES ('wot', 'http://xmlns.com/wot/0.1/');
INSERT INTO namespace VALUES ('x', 'http://www.softwarestudio.org/libical/UsingLibical/node49.html#');
INSERT INTO namespace VALUES ('xfn', 'http://gmpg.org/xfn/1#');
INSERT INTO namespace VALUES ('xhtml', 'http://www.w3.org/1999/xhtml');
INSERT INTO namespace VALUES ('xlink', 'http://www.w3.org/1999/xlink/');
INSERT INTO namespace VALUES ('xml', 'http://www.w3.org/XML/1998/namespace');
INSERT INTO namespace VALUES ('xsd', 'http://www.w3.org/2001/XMLSchema#');
INSERT INTO namespace VALUES ('dbpedia', 'http://dbpedia.org/property/');
INSERT INTO namespace VALUES ('dbo', 'http://dbpedia.org/ontology/');
INSERT INTO namespace VALUES ('prov', 'http://www.w3.org/ns/prov#');
INSERT INTO namespace VALUES ('vcard', 'http://www.w3.org/2006/vcard/ns#');
INSERT INTO namespace VALUES ('ical', 'http://www.w3.org/2002/12/cal/icaltzd#');
INSERT INTO namespace VALUES ('m3c', 'http://www.m3c.si/xmlns/m3c/2006-06#');
INSERT INTO namespace VALUES ('akt', 'http://www.aktors.org/ontology/portal#');
INSERT INTO namespace VALUES ('an', 'http://www.w3.org/2000/10/annotation-ns#');
INSERT INTO namespace VALUES ('bib', 'http://www.isi.edu/webscripter/bibtex.o.daml#');
INSERT INTO namespace VALUES ('conf2', 'http://www.mindswap.org/~golbeck/web/www04photo.owl#');
INSERT INTO namespace VALUES ('contact', 'http://www.w3.org/2000/10/swap/pim/contact#');
INSERT INTO namespace VALUES ('daml', 'http://www.daml.org/2001/03/daml+oil#');
INSERT INTO namespace VALUES ('doa', 'http://www.daml.org/2001/10/html/airport-ont#');
INSERT INTO namespace VALUES ('doap', 'http://usefulinc.com/ns/doap#');
INSERT INTO namespace VALUES ('exif', 'http://www.w3.org/2000/10/swap/pim/exif#');
INSERT INTO namespace VALUES ('foaf', 'http://xmlns.com/foaf/0.1/');
INSERT INTO namespace VALUES ('georss', 'http://www.georss.org/georss/');
INSERT INTO namespace VALUES ('ical2', 'http://www.w3.org/2002/12/cal/ical#');
INSERT INTO namespace VALUES ('iwi', 'http://www.iwi-iuk.org/material/RDF/Schema/Class/iwi#');
INSERT INTO namespace VALUES ('log', 'http://www.w3.org/2000/10/swap/log#');
INSERT INTO namespace VALUES ('midesc', 'http://www.iwi-iuk.org/material/RDF/Schema/Descriptor/midesc#');
INSERT INTO namespace VALUES ('rssmn', 'http://usefulinc.com/rss/manifest/');
INSERT INTO namespace VALUES ('mn', 'http://www.iwi-iuk.org/material/RDF/1.1/Schema/Class/mn#');
INSERT INTO namespace VALUES ('otest', 'http://www.w3.org/2002/03owlt/testOntology#');
INSERT INTO namespace VALUES ('rev', 'http://www.purl.org/stuff/rev#');
INSERT INTO namespace VALUES ('rtest', 'http://www.w3.org/2000/10/rdf-tests/rdfcore/testSchema#');
INSERT INTO namespace VALUES ('sioc', 'http://rdfs.org/sioc/ns#');
INSERT INTO namespace VALUES ('swrc', 'http://swrc.ontoware.org/ontology#');
INSERT INTO namespace VALUES ('swivt', 'http://semantic-mediawiki.org/swivt/1.0#');
INSERT INTO namespace VALUES ('csi', 'http://culture.si/en/Special:URIResolver/');


--
-- Name: config_pkey; Type: CONSTRAINT; Schema: sparql; Owner: sparql; Tablespace: 
--

ALTER TABLE ONLY config
    ADD CONSTRAINT config_pkey PRIMARY KEY (name);


--
-- Name: endpoint_pkey; Type: CONSTRAINT; Schema: sparql; Owner: sparql; Tablespace: 
--

ALTER TABLE ONLY endpoint
    ADD CONSTRAINT endpoint_pkey PRIMARY KEY (name);

