-- PgSPARQL - SQL/SPARQL utilities
-- version 2.0
-- (c) Ziga Kranjec <ziga@ljudmila.org>
-- License: PostgreSQL license

-- This file contains SQL to upgrade from version 1.0 to version 2.0
-- Contents:
--   FUNCTION sparql.sparql_lexize(text)
--   FUNCTION sparql.sparql_lexize_table(text)
--   FUNCTION sparql.sparql_parser(text[])
--   FUNCTION sparql.sparql_parse(text)


CREATE OR REPLACE FUNCTION sparql.sparql_lexize(text)
 RETURNS text[]
 LANGUAGE plperl
 STRICT
AS $function$
use strict; use warnings;

my $i; my $o;
my $input = shift;
my @r;
my $keywords = { 
	'PREFIX'=>1, 'SELECT'=>1, 'DISTINCT'=>1, 'REDUCED'=>1,
    'FROM'=>1, 'VALUES'=>1, 'NAMED'=>1, 'GRAPH'=>1, 'SERVICE'=>1,
	'WHERE'=>1, 'OPTIONAL'=>1, 'FILTER'=>1,
    'NOT'=>1, 'EXISTS'=>1, 'UNION'=>1, 'MINUS'=>1,
    'GROUP'=>1, 'BY'=>1, 'HAVING'=>1, 
    'ORDER'=>1, 'ASC'=>1, 'DESC'=>1,
    'OFFSET'=>1, 'LIMIT'=>1,
    'CONSTRUCT'=>1, 'ASK'=>1, 'DESCRIBE'=>1,
    'INSERT'=>1, 'DATA'=>1
};

$o=0; $i=0;
while(length($input)>0) {
	my ($s,$t);
	# white space
	   if($input=~s/^(\s+)//s) 
		{ $t=' '; }
	# comments
	elsif($input=~s/^(#.*)//) 
		{ $t='#'; }
	# iriref 
	elsif($input=~s/^(<([^<>\{\}\|^`\\\x00-\x20]*)>)//) 
		{ $t='IRIREF'; }
	# variables 
	elsif($input=~s/^([\$\?][\w0-9_]+)//) 
		{ $t='VAR'; }
	# strings
	elsif($input=~s/^('([^\x27\x5c\x0a\x0d]|\\[\\tbnrf\x22\x27])*?')//s) 
		{ $t='STRING1'; }
	elsif($input=~s/^("([^\x27\x5c\x0a\x0d]|\\[\\tbnrf\x22\x27'])*?")//s) 
		{ $t='STRING2'; }
	elsif($input=~s/^(\@[a-zA-Z]+(-[a-zA-Z0-9]+)?)//) 
		{ $t='LANGTAG'; }
	elsif($input=~s/^(\^\^)//) 
		{ $t='DATATYPE'; }
	# anon and nil
	elsif($input=~s/^(\[\s*\])//s) 
		{ $t='ANON'; }
	elsif($input=~s/^(\(\s*\))//s) 
		{ $t='NIL'; }
    ## other
	elsif($input=~s/^(!=|>=|<=|[!<>=+\-\*\/]|\|\||\&\&|IN|NOT\s+IN)//is) 
		{ $t='OP'; }
    # puntuation separators
	elsif($input=~s/^([\.;,])//) 
		{ $t='SEP'; }
    # block begin
	elsif($input=~s/^([\{\(])//) 
		{ $t='BEGIN'; }
    # block end
	elsif($input=~s/^([\}\)])//) 
		{ $t='END'; }
    # long property names
	elsif($input=~s/^([\w\d]+:[\w\d]+)//) 
		{ $t='PROPERTY'; }
    # prefixes
	elsif($input=~s/^((\w([\w\.]*\w)?)?:)//) 
		{ $t='PREFIX'; }
	# words
	elsif($input=~s/^(\w+)//) { 
		my $kw=uc($1);
		if($keywords->{$kw}) { $s=$kw; $t='KEYWORD'; }
		else { $t='WORD'; }
	}
	## unknown ???
	if(!defined($t)) {
	    $input=~s/^(.+)//; $s=$1;
	    elog WARNING,qq{SPARQL_LEXIZE: unrecognized token "$1"};
	}
	if(!defined($s)) { $s=$1; }
	$i++; # update lexeme counter
	if($t ne ' ') { # if not whitespace
		push @r,[$s,$t,$o];
	}
	$o+=length($s); # update offset
 }

return [@r];
$function$
;

CREATE OR REPLACE FUNCTION sparql.sparql_lexize_table(text)
 RETURNS TABLE(o integer, token text, tag text)
 LANGUAGE sql
AS $function$
select (e->>2)::int as o,e->>0 as token,e->>1 as type
 from jsonb_array_elements(to_jsonb(sparql.sparql_lexize($1))) e;
$function$
;

-- DROP FUNCTION sparql.sparql_parser(_text);

CREATE OR REPLACE FUNCTION sparql.sparql_parser(text[])
 RETURNS json
 LANGUAGE plperlu
AS $function$
use strict;
use warnings;
use JSON -convert_blessed_universally;

my $lex = shift;    # lexed query passed as parameter
$lex=$lex->{array}; # unwrap it

my $r = {}; # result goes here
my $l;      # current lexeme (all of data)
my $str;    # current string
my $tag;    # current tag

my $pop = sub { 
	my $type = shift;
	$l = shift @$lex; 
    $str = $l->[0]; $tag = $l->[1];
	if(defined($type) && $type ne $tag) {
		if($type ne $tag) {
	      elog WARNING,
            qq{SPARQL_PARSER: unexpected token "$str"; }.
            qq{expecting $type got $tag};
        }
	}
	return $str;
};

my $parse_prologue = sub {
	my ($r)=@_;
	while($l->[0] eq 'PREFIX') {
#		if(!defined($r->{namespaces})) { $r->{namespaces}={}; }
		my $prefix = $pop->('PREFIX');
		my $uri = $pop->('IRIREF');
		$r->{namespaces}->{$prefix}=$uri;
		$pop->();
	}
};

$pop->();
$parse_prologue->($r);

my $json = JSON->new->allow_nonref->convert_blessed;
   $json = $json->encode($r);
utf8::decode($json);
return $json;
$function$
;

CREATE OR REPLACE FUNCTION sparql.sparql_parse(text)
 RETURNS json
 LANGUAGE sql
AS $function$
select sparql.sparql_parser(sparql.sparql_lexize($1));
$function$
;
