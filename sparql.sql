CREATE SCHEMA sparql;

COMMENT ON SCHEMA sparql IS 'Interface to Virtuoso SPARQL endpoint';

SET search_path = sparql, pg_catalog;

--
-- Name: iri; Type: DOMAIN; Schema: sparql; Owner: sparql
--

CREATE DOMAIN iri AS text;

--
-- Name: compile_query(name, text, text, name[]); Type: FUNCTION; Schema: sparql; Owner: ziga
--

CREATE FUNCTION compile_query(endpoint_name name, identifier text, query text, group_by name[] DEFAULT NULL::name[]) RETURNS text
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
	  else { push @a,qq{array_agg(distinct "$w1") as "$w1"}; }
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

--
-- Name: config(text); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE FUNCTION config(var text) RETURNS text
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

CREATE FUNCTION endpoint_url(endpoint_name name) RETURNS text
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

CREATE FUNCTION get_properties(endpoint_name name, iri text, OUT predicate text, OUT object text, OUT value text, OUT lang text) RETURNS SETOF record
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
 (?p as ?predicate), 
 (?o as ?object),
 (coalesce(?lo, ?o) as ?value),
 (lang(?lo) as ?lang)
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

--
-- Name: FUNCTION get_properties(endpoint_name name, iri text, OUT predicate text, OUT object text, OUT value text, OUT lang text); Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON FUNCTION get_properties(endpoint_name name, iri text, OUT predicate text, OUT object text, OUT value text, OUT lang text) IS 'Get properties for RDF resource from SPARQL endpoint';


--
-- Name: iri_ident(text); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE FUNCTION iri_ident(text) RETURNS text
    LANGUAGE plperl IMMUTABLE
    AS $_$
  my ($url)=@_;
  if($url=~s!([/#])([_\-a-zA-Z0-9]+)$!$1!) { return $2; }
  return undef;
$_$;

--
-- Name: iri_prefix(text); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE FUNCTION iri_prefix(text) RETURNS text
    LANGUAGE plperl IMMUTABLE
    AS $_$
  my ($url)=@_;
  if($url=~s!([/#])([_\-a-zA-Z0-9]+)$!$1!) { return $url; }
  return undef;
$_$;

--
-- Name: properties(name); Type: FUNCTION; Schema: sparql; Owner: sparql
--

CREATE FUNCTION properties(endpoint_name name, OUT pred text, OUT label text, OUT comment text, OUT cardinality text, OUT range text, OUT "isDefinedBy" text) RETURNS SETOF record
    LANGUAGE plperlu COST 5000
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

COMMENT ON FUNCTION properties(endpoint_name name, OUT pred text, OUT label text, OUT comment text, OUT cardinality text, OUT range text, OUT "isDefinedBy" text) IS 'Compiled with sparql.compile_query()';

SET default_with_oids = false;

--
-- Name: config; Type: TABLE; Schema: sparql; Owner: sparql; Tablespace: 
--

CREATE TABLE config (
    name text NOT NULL,
    value text,
    regtype regtype DEFAULT 'text'::regtype NOT NULL,
    comment text
);


ALTER TABLE config OWNER TO sparql;

--
-- Name: TABLE config; Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON TABLE config IS 'Various configuration options';

--
-- Name: endpoint; Type: TABLE; Schema: sparql; Owner: sparql; Tablespace: 
--

CREATE TABLE endpoint (
    name name NOT NULL,
    url text NOT NULL
);


ALTER TABLE endpoint OWNER TO sparql;

--
-- Name: TABLE endpoint; Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON TABLE endpoint IS 'SPARQL endpoint definitions';


--
-- Name: namespace; Type: TABLE; Schema: sparql; Owner: sparql; Tablespace: 
--

CREATE TABLE namespace (
    name name NOT NULL,
    uri iri
);

--
-- Name: TABLE namespace; Type: COMMENT; Schema: sparql; Owner: sparql
--

COMMENT ON TABLE namespace IS 'Table of common RDF namespaces';

COPY config (name, value, regtype, comment) FROM stdin;
\.


--
-- Data for Name: endpoint; Type: TABLE DATA; Schema: sparql; Owner: sparql
--

COPY endpoint (name, url) FROM stdin;
dbpedia	http://dbpedia.org/sparql/
geonames	http://www.lotico.com:3030/lotico/sparql
wikidata	https://query.wikidata.org/bigdata/namespace/wdq/sparql
\.


--
-- Data for Name: namespace; Type: TABLE DATA; Schema: sparql; Owner: sparql
--

COPY namespace (name, uri) FROM stdin;
NC	http://home.netscape.com/NC-rdf#
NS0	http://www.daml.org/2002/02/telephone/1/areacodes-ont#
a1	http://protege.stanford.edu/system#
a2	http://www.cogsci.princeton.edu/~wn/concept#
admin	http://webns.net/mvcb/
ag	http://purl.org/rss/1.0/modules/aggregation/
air	http://www.megginson.com/exp/ns/airports#
ajft	http://ajft.org/foaf.rdf#
an2	http://rdf.desire.org/vocab/recommend.rdf#
annotate	http://purl.org/rss/1.0/modules/annotate/
app	http://example.com/app#
assert	http://ebiquity.umbc.edu/ontology/assertion.owl#
assoc	http://ebiquity.umbc.edu/ontology/association.owl#
at	http://www.sixapart.com/ns/at
attribute	http://wiki.ontoworld.org/index.php/_Attribute-3A
b	http://www.cogsci.princeton.edu/~wn/schema/
base	http://www.aktors.org/ontology/base#
bbc	http://bbc.co.uk/ns#
bio	http://purl.org/vocab/bio/0.1/
bk	http://www.hackcraft.net/bookrdf/vocab/0_1/
blogChannel	http://backend.userland.com/blogChannelModule
bulkfeeds	http://bulkfeeds.net/xmlns#
bz	http://bitzi.com/xmlns/2002/01/bz-core#
canon	http://nwalsh.com/rdf/exif-canon#
cap	http://impressive.net/people/gerald/2001/captivate-ns#
card	http://person.org/BusinessCard/
cc	http://web.resource.org/cc/
ccpp	http://www.w3.org/2000/07/04-ccpp#
ccpp2	http://www.w3.org/2002/11/08-ccpp-schema#
chefmoz	http://chefmoz.org/rdf/elements/1.0/
chrome	http://www.mozilla.org/rdf/chrome#
cld	http://www.ukoln.ac.uk/metadata/rslp/1.0/
clique	http://russell.rucus.net/2004/clique/#
cmet	http://veggente.berlios.de/ns/RIM_CMET#
co	http://purl.org/rss/1.0/modules/company/
conf	http://www.mindswap.org/2004/www04photo.owl#
confoto	http://www.confoto.org/ns/confoto#
contact2	http://ebiquity.umbc.edu/ontology/contact.owl#
content	http://purl.org/rss/1.0/modules/content/
cvs	http://nwalsh.com/rdf/cvs#
cyc	http://opencyc.sourceforge.net/daml/cyc.daml#
daml2	http://www.daml.org/2000/10/daml-ont#
date	java:java.util.Date
dc10	http://purl.org/dc/elements/1.0/
dc	http://purl.org/dc/elements/1.1/
dcq1	http://dublincore.org/2000/03/13/dcq#
dcq	http://purl.org/dc/qualifiers/1.0/
dct	http://dublincore.org/2000/03/13-dctype
dcterms	http://purl.org/dc/terms/
dctype1	http://dublincore.org/2003/12/08/dctype#
dctype	http://purl.org/dc/dcmitype/
doap2	http://usefulinc.com/ns/doap/#
doc	http://www.w3.org/2000/10/swap/pim/doc#
e	http://eulersharp.sourceforge.net/2003/03swap/log-rules#
ecademy	http://www.ecademy.com/namespace/
eg	http://example.org/
enc	http://purl.oclc.org/net/rss_2.0/enc#
ent	http://jena.hpl.hp.com/ENT/1.0/#
eor	http://dublincore.org/2000/03/13/eor#
ethan	http://spire.umbc.edu/ontologies/ethan.owl#
ev	http://purl.org/rss/1.0/modules/event/
event	http://ebiquity.umbc.edu/ontology/event.owl#
ex1	http://example.org/stuff/1.0/
ex	http://www.example.com/schema#
exif4	http://impressive.net/people/gerald/2001/exif#
exif3	http://nwalsh.com/rdf/exif#
exif2	http://www.kanzaki.com/ns/exif#
exifgps	http://nwalsh.com/rdf/exif-gps#
exifi	http://nwalsh.com/rdf/exif-intrinsic#
feedburner	http://rssnamespace.org/feedburner/ext/1.0
file	http://www.w3.org/2000/10/swap/pim/file#
flair	http://simile.mit.edu/2005/04/flair#
fotonotes	http://fotonotes.net/rdf/fotonotes-schema#
g	http://www.w3.org/2001/02pd/gv#
gal	http://norman.walsh.name/rdf/gallery#
geoinsee	http://rdf.insee.fr/geo/
geo	http://www.w3.org/2003/01/geo/wgs84_pos#
gps	http://hackdiary.com/ns/gps#
gump	http://gump.apache.org/schemas/main/1.0/
hl7	urn:hl7-org:v3/mif
http	http://www.w3.org/1999/xx/http#
iX	http://ns.adobe.com/iX/1.0/
ical1	http://www.w3.org/2002/12/cal/#
image	http://jibbering.com/vocabs/image/#
img1	http://igargoyle.com/rss/1.0/modules/img/
img2	http://jibbering.com/2002/3/svg/#
imreg	http://www.w3.org/2004/02/image-regions#
iw	http://inferenceweb.stanford.edu/2004/07/iw.owl#
iwip	http://www.iwi-iuk.org/material/RDF/Schema/Property/iwip#
jms	http://jena.hpl.hp.com/2003/08/jms#
jpegrdf	http://nwalsh.com/rdf/jpegrdf#
keyword	http://animaldiversity.ummz.umich.edu/local/keywords/keywords.owl#
ethan_kw	http://spire.umbc.edu/ontologies/ethan_keywords.owl#
l	http://purl.org/rss/1.0/modules/link/
lang	http://purl.org/net/inkel/rdf/schemas/lang/1.1#
marc	http://www.loc.gov/marc/relators/
mat	http://www.w3.org/2002/05/matrix/vocab#
math	http://www.w3.org/2000/10/swap/math#
mathind	http://www.math.org/#
mcc	http://mutemap.openmute.org/2003/mcc#
mesh	http://www.nlm.nih.gov/mesh/2004#
mindswap	http://www.mindswap.org/2003/owl/mindswap#
mindswap-projects	http://www.mindswap.org/2004/owl/mindswap-projects#
mindswappers	http://www.mindswap.org/2004/owl/mindswappers#
mm20	http://musicbrainz.org/mm/mm-2.0#
mm21	http://musicbrainz.org/mm/mm-2.1#
mms	http://www.openmobilealliance.org/tech/profiles/MMS/ccppschema-20050301-MMS1.2#
mmswap	http://www.wapforum.org/profiles/MMS/ccppschema-20010111#
mnp	http://www.iwi-iuk.org/material/RDF/1.1/Schema/Property/mnp#
mnst	http://www.iwi-iuk.org/material/RDF/1.1/descriptor/#
moblog	http://kaywa.com/rss/modules/moblog/
modwiki	http://www.usemod.com/cgi-bin/mb.pl?ModWiki
mp	http://www.mutopiaproject.org/piece-data/0.1/
mu	http://storymill.com/mu/2005/03/
neg	http://www.inrialpes.fr/opera/people/Tayeb.Lemlouma/NegotiationSchema/ClientProfileSchema-03012002#
news	http://www.nature.com/schema/2004/05/news#
nhet	http://spire.umbc.edu/ontologies/nhet.owl#
nikon	http://nwalsh.com/rdf/exif-nikon5700#
nikon950	http://nwalsh.com/rdf/exif-nikon950#
nines	http://www.nines.org/schema#
nlo	http://nulllogicone.net/schema.rdfs#
nwn-what	http://norman.walsh.name/knows/what#
nwn-where	http://norman.walsh.name/knows/where#
nwn-who	http://norman.walsh.name/knows/who#
oiled	http://img.cs.man.ac.uk/oil/oiled#
ontosem	http://morpheus.cs.umbc.edu/aks1/ontosem.owl#
ontoware	http://swrc.ontoware.org/ontology/ontoware#
org	http://www.w3.org/2001/04/roadmap/org#
os	http://downlode.org/rdf/os/0.1/
owl	http://www.w3.org/2002/07/owl#
p	http://www.usefulinc.com/picdiary/
p0	http://eulersharp.sourceforge.net/2003/03swap/xsd-rules#
p1	http://eulersharp.sourceforge.net/2003/03swap/rdfs-rules#
person	http://ebiquity.umbc.edu/ontology/person.owl#
pm	http://mindswap.org/2005/owl/photomesa#
prf	http://www.openmobilealliance.org/tech/profiles/UAPROF/ccppschema-20021212#
prfwap	http://www.wapforum.org/profiles/UAPROF/ccppschema-20010430#
prism	http://prismstandard.org/namespaces/1.2/basic/
process10	http://www.daml.org/services/owl-s/1.0/Process.owl#
process11	http://www.daml.org/services/owl-s/1.1/Process.owl#
profile	http://www.daml.org/services/owl-s/1.0/Profile.owl#
project	http://ebiquity.umbc.edu/ontology/project.owl#
project2	http://www.mindswap.org/2003/owl/project#
protege	http://protege.stanford.edu/plugins/owl/protege#
pub	http://ebiquity.umbc.edu/ontology/publication.owl#
q	http://www.w3.org/2004/ql#
ra	http://www.rossettiarchive.org/schema#
random	http://random.ioctl.org/#
rcs	http://www.w3.org/2001/03swell/rcs#
rdf	http://www.w3.org/1999/02/22-rdf-syntax-ns#
rdfs	http://www.w3.org/2000/01/rdf-schema#
rec	http://www.w3.org/2001/02pd/rec54#
ref	http://purl.org/rss/1.0/modules/reference/
rel	http://purl.org/vocab/relationship/
relation	http://wiki.ontoworld.org/index.php/_Relation-3A
research	http://ebiquity.umbc.edu/ontology/research.owl#
rim_dt	http://veggente.berlios.de/ns/RIMDatatype#
role	http://www.loc.gov/loc.terms/relators/
rs	http://www.w3.org/2001/sw/DataAccess/tests/result-set#
rss2	http://backend.userland.com/RSS2#
rss1	http://purl.org/rss/1.0/
s	http://snipsnap.org/rdf/snip-schema#
schemaweb	http://www.schemaweb.info/schemas/meta/rdf/
s0	http://www.w3.org/2000/PhotoRDF/dc-1-0#
s1	http://sophia.inria.fr/~enerbonn/rdfpiclang#
se	http://www.w3.org/2004/02/skos/extensions#
semblog	http://www.semblog.org/ns/semblog/0.1/
service	http://www.daml.org/services/owl-s/1.0/Service.owl#
signage	http://www.aktors.org/ontology/signage#
skos	http://www.w3.org/2004/02/skos/core#
slash	http://purl.org/rss/1.0/modules/slash/
smw	http://smw.ontoware.org/2005/smw#
space	http://frot.org/space/0.1/
spi	http://www.trustix.net/schema/rdf/spi-0.0.1#
str	http://www.w3.org/2000/10/swap/string#
support	http://www.aktors.org/ontology/support#
svgr	http://www.w3.org/2001/svgRdf/axsvg-schema.rdf#
swrl	http://www.w3.org/2003/11/swrl#
sy	http://purl.org/rss/1.0/modules/syndication/
sy0	http://purl.org/rss/modules/syndication/
tax	http://semweb.mcdonaldbradley.com/OWL/TaxonomyMapping/Definitions/TaxonomySupport.owl#
taxo	http://purl.org/rss/1.0/modules/taxonomy/
template	http://redfoot.net/2005/template#
terms	http://jibbering.com/2002/6/terms#
thes	http://reports.eea.eu.int/EEAIndexTerms/ThesaurusSchema.rdf#
thing	http://wiki.ontoworld.org/index.php/_
ti	http://purl.org/rss/1.0/modules/textinput/
tif	http://www.limber.rl.ac.uk/External/thesaurus-iso.rdf#
trackback	http://madskills.com/public/xml/rss/module/trackback/
trust	http://trust.mindswap.org/ont/trust.owl#
units	http://visus.mit.edu/fontomri/0.01/units.owl#
ure	http://medea.mpiwg-berlin.mpg.de/ure/vocab#
urfm	http://purl.org/urfm/
uri	http://www.w3.org/2000/07/uri43/uri.xsl?template=
vCard	http://www.w3.org/2001/vcard-rdf/3.0#
vann	http://purl.org/vocab/vann/
vlma	http://medea.mpiwg-berlin.mpg.de/vlma/vocab#
vra	http://www.swi.psy.uva.nl/mia/vra#
vs	http://www.w3.org/2003/06/sw-vocab-status/ns#
wfw	http://wellformedweb.org/CommentAPI/
wiki	http://purl.org/rss/1.0/modules/wiki/
wikiped	http://en.wikipedia.org/wiki/
wn	http://xmlns.com/wordnet/1.6/
wot	http://xmlns.com/wot/0.1/
x	http://www.softwarestudio.org/libical/UsingLibical/node49.html#
xfn	http://gmpg.org/xfn/1#
xhtml	http://www.w3.org/1999/xhtml
xlink	http://www.w3.org/1999/xlink/
xml	http://www.w3.org/XML/1998/namespace
xsd	http://www.w3.org/2001/XMLSchema#
dbpedia	http://dbpedia.org/property/
vcard	http://www.w3.org/2006/vcard/ns#
ical	http://www.w3.org/2002/12/cal/icaltzd#
m3c	http://www.m3c.si/xmlns/m3c/2006-06#
akt	http://www.aktors.org/ontology/portal#
an	http://www.w3.org/2000/10/annotation-ns#
bib	http://www.isi.edu/webscripter/bibtex.o.daml#
conf2	http://www.mindswap.org/~golbeck/web/www04photo.owl#
contact	http://www.w3.org/2000/10/swap/pim/contact#
daml	http://www.daml.org/2001/03/daml+oil#
doa	http://www.daml.org/2001/10/html/airport-ont#
doap	http://usefulinc.com/ns/doap#
exif	http://www.w3.org/2000/10/swap/pim/exif#
foaf	http://xmlns.com/foaf/0.1/
georss	http://www.georss.org/georss/
ical2	http://www.w3.org/2002/12/cal/ical#
iwi	http://www.iwi-iuk.org/material/RDF/Schema/Class/iwi#
log	http://www.w3.org/2000/10/swap/log#
midesc	http://www.iwi-iuk.org/material/RDF/Schema/Descriptor/midesc#
rssmn	http://usefulinc.com/rss/manifest/
mn	http://www.iwi-iuk.org/material/RDF/1.1/Schema/Class/mn#
otest	http://www.w3.org/2002/03owlt/testOntology#
rev	http://www.purl.org/stuff/rev#
rtest	http://www.w3.org/2000/10/rdf-tests/rdfcore/testSchema#
sioc	http://rdfs.org/sioc/ns#
swrc	http://swrc.ontoware.org/ontology#
swivt	http://semantic-mediawiki.org/swivt/1.0#
csi	http://culture.si/en/Special:URIResolver/
\.


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


--
-- Name: namespace_pkey; Type: CONSTRAINT; Schema: sparql; Owner: sparql; Tablespace: 
--

ALTER TABLE ONLY namespace
    ADD CONSTRAINT namespace_pkey PRIMARY KEY (name);

