/* -*-fundamental-*- */
/* $Id$ */

%{
#include "pub_parse.h"
#include "parse.h"
#define YY_STR_BUFLEN 20*1024

static void begin_PSTR (int i, int mode);
static void end_PSTR ();
static void begin_STR (int i, int j);
static void begin_P3_STR ();
static void end_P3_STR ();
static int  end_STR ();
static int addch (int c1, int c2);
static int addstr (const char *c, int l);
static void nlcount (int m = 0);
static void push_p3_func ();
static void pop_p3_func (void);

static void p3_regex_begin (char in);
static int  p3_regex_is_close_char (char c);
static void p3_regex_add (const char *in);
static int  p3_regex_bad_eof ();
static int  p3_regex_finish (const char *opts);
static void p3_regex_escape_sequence (const char *c);

static void bracket_mark_left (int n = 1);
static void bracket_mark_right (void);
static int unbalanced_bracket (void);
static int bracket_check_eof (void);

int yy_ssln;
int yy_wss_nl;
int yywss;
int yyesc;
int yy_oldesc;
int yy_pt_com;  /* pass-throgh comment! */
char str_buf[YY_STR_BUFLEN];
int sbi;
char *eof_tok;
int yy_d_brace;
int yy_d_bracket;
vec<int> yy_d_bracket_linenos;
int yy_p3_depth;

static char yy_p3_regex_close_char;
static char yy_p3_regex_open_char;
static int yy_p3_regex_start_line;
strbuf yy_p3_regex_buf;


%}

%option stack
%option noyywrap

P3IDENT [a-zA-Z_][a-zA-Z_0-9]*
VAR	[a-zA-Z_][a-zA-Z_0-9.]*
HNAM	[a-zA-Z_][a-zA-Z_0-9-]*
HVAL	[^ \t\n\r"'>=$]*[^ \t\n\r/"'>=$]
ST	[Ss][Cc][Rr][Ii][Pp][Tt]
PRET    [Pp][Rr][Ee]
WS	[ \t]
WSN	[ \t\n]
EOL	[ \t]*\n?
TPRFX	(<!--#|\{%)[ \t]*
TPRFX1  (<!--#)[ \t]*
TPRFX3  \{%[ \t\n]*
TCLOSE	[ \t]*[;]?[ \t]*(-->|%\})

%x STR SSTR H HTAG PTAG PSTR PVAR WH HCOM JS
%x PRE PSTR_SQ TXLCOM TXLCOM3 POUND_REGEX 
%x P3 P3_STR P3_REGEX

%%

<INITIAL>\n	{ PLINC; return ('\n'); }

<PTAG>{
(-->|%\})		{ yy_pop_state (); return T_EPTAG; }
}

<PTAG>{
{WS}+		/* discard */ ;
\n		{ PLINC; }

=>		|
[(),{}=;]	return yytext[0];


m#		{ yy_push_state (POUND_REGEX); return T_REGEX_BEGIN; }
r#		{ yy_push_state (POUND_REGEX); return T_RANGE_BEGIN; }


int(32(_t)?)?[(]	return T_INT_ARR; 
char[(]			return T_CHAR_ARR;
int64(_t)?[(]		return T_INT64_ARR;
int16(_t)?[(]		return T_INT16_ARR;

u_int(32(_t)?)?[(]	return T_UINT_ARR;
u_int16(_t)?[(]		return T_UINT16_ARR;


{VAR}		{ yylval.str = yytext; return T_VAR; }

[+-]?[0-9]+	|
[+-]?0x[0-9]+	{ yylval.str = yytext; return T_NUM; }

\"		{ begin_PSTR (1, PSTR); return (yytext[0]); }

"//".*$		/* discard */ ;

.		{ return yyerror ("illegal token found in PTAG environment"); }
}

<H>\n			{ PLINC; return (yytext[0]); }

<H,WH>{
{TPRFX1}include		{ yy_push_state (PTAG); return T_PTINCLUDE; }
{TPRFX1}load		{ yy_push_state (PTAG); return T_PTLOAD; }
{TPRFX1}inclist		{ yy_push_state (PTAG); return T_PTINCLIST; }
{TPRFX1}setl		{ yy_push_state (PTAG); return T_PTSETL; }
{TPRFX1}set		{ yy_push_state (PTAG); return T_PTSET; }
{TPRFX1}switch		{ yy_push_state (PTAG); return T_PTSWITCH; }
{TPRFX1}"#"	    	|
{TPRFX1}com(ment)?	{ yy_pt_com = 0; yy_push_state (HCOM); }
{TPRFX1}[Rr][Ee][Mm]	{ 
			  yy_pt_com = 1; 
 			  begin_STR (HCOM, 0);
			  addstr ("<!--", 4);
	  		}

{TPRFX3}for             { push_p3_func (); return T_P3_FOR; }
{TPRFX3}(cond|if)	{ push_p3_func (); return T_P3_COND; }
{TPRFX3}include		{ push_p3_func (); return T_P3_INCLUDE; }
{TPRFX3}load            { push_p3_func (); return T_P3_LOAD; }
{TPRFX3}set		{ push_p3_func (); return T_P3_SET; }
{TPRFX3}setl		{ push_p3_func (); return T_P3_SETL; }
}

<POUND_REGEX>{
[^#\\]+|\\#|\\	{ yylval.str = yytext; return T_REGEX_BODY; }
#[a-zA-Z]*	{ 
		   yy_pop_state ();
                   yylval.str = yytext + 1; 
                   return T_REGEX_END; 
                }
}


<TXLCOM3>{
"]"{3}		{ 
		   yy_d_bracket --;
                   bracket_mark_right ();
		   yy_pop_state (); 
                }
\n		{ PLINC; }
[^\]\n]+	{ /* ignore */; }
}

<TXLCOM>{
"[["		{ yy_d_bracket++; bracket_mark_left (); }
\\"[""["+	{ /* ignore */ ; }

"["		|
"\\"		|
"]"		|
[^\]\[\\\n]+	{ /* ignore */ ; }

"]]"		{ 
		   yy_d_bracket--; 
		   bracket_mark_right();
		   if (yy_d_bracket <= 1) { yy_pop_state (); } 
                }

\n		{ PLINC; }
}


<H,WH,JS,PSTR,PTAG,HTAG,PSTR_SQ>{
"${"		{ 
		      yy_push_state (PVAR); 
		      return T_BVAR; 
		}

"%{"		{
		      yy_push_state (P3);
		      return T_P3_BEGIN_EXPR;
		}

\\+[$%]"{"	|
\\"}}"          { yylval.str = yytext + 1; return T_HTML; }

"}}"		{ if (yy_d_brace > 0) {
		     yy_d_brace -- ;
		     yy_pop_state ();
                     return T_2R_BRACE; 
	          } else {
	 	     yylval.str = yytext; return T_HTML;
	          } 
                } 

[%$}\[\]]	{ yylval.ch = yytext[0]; return T_CH; }
}

<H,WH,JS,PSTR,PTAG,HTAG,PSTR_SQ,P3_STR>{
"[[[["		{
		   yy_d_bracket += 2;
		   bracket_mark_left (2);
		   yy_push_state (TXLCOM);
		}

"[[["		{
		   yy_d_bracket += 1;
		   bracket_mark_left (1);

		   if (yy_d_bracket == 1) {
		      yy_push_state (TXLCOM3);
		   } else {
		      yy_push_state (TXLCOM);
		   }
		}

"[["		{
		   yy_d_bracket ++;
		   bracket_mark_left (1);
		   if (yy_d_bracket > 1) 
		     yy_push_state (TXLCOM);
		}

"]]"		{ 
                  if (yy_d_bracket > 0) {
		     bracket_mark_right ();
		     yy_d_bracket--;
                  } else {
		     yylval.str = yytext;
		     return T_HTML;
		  }
                }

\\"["{2,4}	|
\\"]]"	        { yylval.str = yytext + 1; return T_HTML; }
}


<H,WH,JS,PTAG,HTAG,TXLCOM,TXLCOM3>{
<<EOF>>		{  return bracket_check_eof(); }
}

<H>{
[^%$}{\\<\[\]]+	{ yylval.str = yytext; nlcount (); return T_HTML; }
[<{]		{ yylval.ch = yytext[0]; return T_CH; }
}

<H>{
\\		{ yylval.ch = yytext[0]; return T_CH; }
}


<H,WH>{	
[<]{PRET}{WSN}*[>] { yy_push_state (PRE); nlcount (); yylval.str = yytext; 
	          return T_BPRE; }
}
<WH>{
{WSN}+		{ nlcount (); return (' '); }
"<!"		{ yylval.str = yytext; return T_HTML; }
[<][/?%]?	{ yy_push_state (HTAG); yylval.str = yytext; return T_BTAG; }
\<{ST}/[ \t\n>]	{ yy_push_state (JS); yy_push_state (HTAG); 
	          yylval.str = yytext; return T_BJST; }

{TPRFX}{ST}{TCLOSE} { yy_push_state (JS); return T_BJS_SILENT; }

\<!--		{ yy_pt_com = 0; yy_push_state (HCOM); }


}

<PRE>{
[^<]+		{ yylval.str = yytext; nlcount (); return T_HTML; }
"</"{PRET}\>	{ yy_pop_state (); yylval.str = yytext; return T_EPRE; }
\<		{ yylval.ch = yytext[0]; return T_CH; }
}

<JS>{
"</"{ST}{WS}*\>	{ yy_pop_state (); yylval.str = yytext; return T_EJS; }
{TPRFX}"/"{ST}{TCLOSE} { yy_pop_state (); return T_EJS_SILENT; }
[}$%<\\]	{ yylval.ch = yytext[0]; return T_CH; }
[^\\$%<}]+	{ yylval.str = yytext; nlcount (); return T_HTML; }
}

<HCOM>{
\n		{ PLINC; if (yy_pt_com) { addch (yytext[0], -1); } }
--\>		{ 
		   if (yy_pt_com) {
			addstr (yytext, yyleng);
			end_STR (); /* calls yy_pop_state (); */
			return T_HTML;
		   } else {
			yy_pop_state ();
		   }
		}

[^-\n]*		{ if (yy_pt_com) { addstr (yytext, yyleng); } }
-		{ if (yy_pt_com) { addch (yytext[0], -1); } }
}

<WH>{
[^$%\\<{\n\t}\[\] ]+	{ yylval.str = yytext; return T_HTML; }
\\		 	{ yylval.ch = yytext[0]; return T_CH; }
}

<HTAG>{
\n		{ PLINC; }
["]		{ begin_PSTR (0, PSTR); return (yytext[0]); }
[']		{ begin_PSTR (0, PSTR_SQ); return (yytext[0]); }

[%?/]?">" 	{ yy_pop_state (); yylval.str = yytext; return T_ETAG; }

{WS}+		/* discard */;
{HNAM}		{ yylval.str = yytext; return T_HNAM; }
{HVAL}		{ yylval.str = yytext; return T_HVAL; }
=		{ return (yytext[0]); }
.		{ return yyerror ("illegal token found in parsed HTAG"); }
}

<SSTR,STR>\n	{ PLINC; addch ('\n', -1); }
<STR>\" 	{ return (end_STR ()); }
<SSTR>\'	{ return (end_STR ()); }

<STR,SSTR>{
\\n  		addch ('\n', 'n');
\\t  		addch ('\t', 't');
\\r		addch ('\r', 'r');
\\b		addch ('\b', 'b');
\\f		addch ('\f', 'f');
\\(.|\n)	addch (yytext[1], yytext[1]);
}

<STR>[^\\\n\"]+		addstr (yytext, yyleng);
<SSTR>[^\\\n\']+	addstr (yytext, yyleng);

<PSTR>{
\n		{ return yyerror ("unterminated parsed string"); }
\\[\\"'tn]	{ if (yyesc) { yylval.ch = yytext[1]; return T_CH; }
	  	  else { yylval.str = yytext; return T_STR; } }
\\.		{ return yyerror ("illegal escape sequence"); }
\"		{ end_PSTR (); return (yytext[0]); }
[^"\\$}\[\]]+	{ yylval.str = yytext; return T_STR; }
}

<PSTR_SQ>{
\n		{ return yyerror ("unterminated parsed string"); }
\\[\\'"tn]	{ if (yyesc) { yylval.ch = yytext[1]; return T_CH; }
	  	  else { yylval.str = yytext; return T_STR; } }
\\.		{ return yyerror ("illegal escape sequence"); }
\'		{ end_PSTR (); return (yytext[0]); }
[^'\\$}\[\]]+	{ yylval.str = yytext; return T_STR; }
}


<STR,PSTR,SSTR,PSTR_SQ>{
<<EOF>>		{ 
		  return yyerror (strbuf ("EOF found in str started on "
                                          "line %d", yy_ssln)); 
		}
}

<PVAR>{
{VAR}		{ yylval.str = yytext; return T_VAR; }
\}		{ yy_pop_state (); return (yytext[0]); }
.		{ return yyerror ("illegal token found in ${..}"); }
}

.		{ return yyerror ("illegal token found in input"); }


<PTAG,P3>{
"{{"		{ 
   	     	   yy_d_brace ++; 
		   yy_push_state (yywss ? WH : H);
	 	   return T_2L_BRACE; 
		}
}

<P3_STR>{
[%$][{]		{ yy_push_state (P3); return T_P3_BEGIN_EXPR; }
\\n		{ yylval.ch = '\n'; return T_P3_CHAR; }
\\t		{ yylval.ch = '\t'; return T_P3_CHAR; }
\\r		{ yylval.ch = '\r'; return T_P3_CHAR; }
\n		{ PLINC; yylval.ch = yytext[0]; return T_P3_CHAR; }
\\.		{ yylval.ch = yytext[1]; return T_P3_CHAR; }
[\[\]]		{ yylval.ch = yytext[1]; return T_P3_CHAR; }
["]		{ end_P3_STR (); return yytext[0]; }
[^\\%$"\n\[\]]+	{ yylval.str = yytext; return T_P3_STRING; }
<<EOF>>         {   
		    bracket_check_eof ();
 		    return yyerror (strbuf ("EOF found in str started on "
		  	 	 	  "line %d", yy_ssln)); 
                }
}

<P3>{

\n		{ PLINC; }

[Tt]rue		{ return T_P3_TRUE; }
[Ff]alse	{ return T_P3_FALSE; }
{P3IDENT}	{ yylval.str = yytext; return T_P3_IDENTIFIER; }
r[#/!@%{<([]	{ p3_regex_begin (yytext[1]); }


([0-9]+|0x[0-9a-f])  { yylval.str = yytext; return T_P3_UINT; }
-?[0-9]*\.[0-9]+     { yylval.str = yytext; return T_P3_FLOAT; }
-[0-9]+              { yylval.str = yytext; return T_P3_INT; }

==		 { return T_P3_EQEQ; }
!=		 { return T_P3_NEQ; }
[<]=		 { return T_P3_LTEQ; }
>=		 { return T_P3_GTEQ; }
=>		 { return yytext[0]; }
[%()!=><,[\].+:-] { return yytext[0]; }
[{]		 { yy_push_state (P3); return yytext[0]; }
[}]		 { yy_pop_state (); return yytext[0]; }
"||"		 { return T_P3_OR; }
"|"		 { return T_P3_PIPE; }
&&		 { return T_P3_AND; }
'[^']'		 { yylval.ch = yytext[1]; return T_P3_CHAR; }
"%}"		 { pop_p3_func (); return T_P3_CLOSETAG; }

[ \t]+		 { /* ignore */ }
["] 		 { begin_P3_STR(); return yytext[0]; }

.		 { return yyerror ("illegal token in Pub v3 environment"); }
}

<P3_REGEX>{
\n			{ PLINC; p3_regex_add (yytext); }
[#/!@%}>)\]][a-zA-Z]*	{ 
			  if (p3_regex_is_close_char (yytext[0])) {
			     return p3_regex_finish (yytext + 1);
			  } else {  
			     p3_regex_add (yytext);
			  }
                        }

\\[#/!@}>)\]]		{ p3_regex_escape_sequence (yytext); }

[^/!@%}>)\]\n\\]+	{ p3_regex_add (yytext); }

<<EOF>>			{
			   return p3_regex_bad_eof ();
			}
}

%%

void
begin_PSTR (int i, int state)
{
  yy_oldesc = yyesc;
  yyesc = i;
  yy_push_state (state);
  yy_ssln = PLINENO;
}

void
end_PSTR ()
{
  yyesc = yy_oldesc;
  yy_pop_state ();
}

void
begin_P3_STR ()
{
  yy_push_state (P3_STR);
  yy_ssln = PLINENO;
}

void
end_P3_STR ()
{
  yy_pop_state ();
}

void
begin_STR (int s, int e)
{
  sbi = 0;
  yy_oldesc = yyesc;
  yyesc = e;
  yy_push_state (s);
  yy_ssln = PLINENO;
}


int
end_STR ()
{
  str_buf[sbi] = '\0';
  yylval.str = str_buf;
  yyesc = yy_oldesc;
  yy_pop_state ();
  return T_STR;
}

int
addch (int c1, int c2)
{
  int len = (yyesc || c2 < 0) ? 1 : 2;
  if (sbi >= YY_STR_BUFLEN - len)
    return yyerror ("string buffer overflow");
  if (yyesc || c2 < 0)
    str_buf[sbi++] = c1;
  else
    sbi += sprintf (str_buf + sbi, "\\%c", c2);
  return 1;
}

int
addstr (const char *s, int l)
{
  if (sbi + l >= YY_STR_BUFLEN - 1)
    return yyerror ("string buffer overflow");
  memcpy (str_buf + sbi, s, l);
  sbi += l;
  return 1;
}

void
nlcount (int m)
{
  int n = 0;
  for (char *y = yytext; *y; y++)
    if (*y == '\n') {
      n++;
      if (m && m == n) 
        break;
    }
  PFILE->inc_lineno (n);
}

int
yyerror (str msg)
{
  if (!msg) 
    msg = "bailing out due to earlier warnings";
  PWARN(msg);
  PARSEFAIL;	
  yyterminate ();
  return 0;
}

int
yywarn (str msg)
{
  PWARN("lexer warning: " << msg);
  return 0;
}

void
yy_push_pubstate (pfile_type_t t)
{
  switch (t) {
  case PFILE_TYPE_CONF:
    yy_push_state (H);
    break;
  case PFILE_TYPE_H:
    yy_push_state (H);
    break;
  case PFILE_TYPE_WH:
    yy_push_state (WH);
    break;
  default:
    fatal << "unknown lexer state\n";
  }
}

void
yy_pop_pubstate ()
{
  yy_pop_state ();
}

void
yyswitch (yy_buffer_state *s)
{
  yy_switch_to_buffer (s);
}

yy_buffer_state *
yycreatebuf (FILE *fp)
{
  return (yy_create_buffer (fp, YY_BUF_SIZE));
}

void
gcc_hack_use_static_functions ()
{
  assert (false);
  char buf[2];
  yyunput (yy_top_state (), buf);
}

void
scanner_reset (void)
{
   yy_d_brace = 0;
   yy_d_bracket = 0;
   yy_d_bracket_linenos.clear ();
}

void
bracket_mark_left (int l)
{
   for (int i = 0; i < l; i++) {
     yy_d_bracket_linenos.push_back (PLINENO);
   }
}

void
bracket_mark_right (void)
{
   if (yy_d_bracket_linenos.size ())
     yy_d_bracket_linenos.pop_back ();
}

int
unbalanced_bracket (void)
{
  int ret = 0;
  if (yy_d_bracket_linenos.size ())
    ret = yy_d_bracket_linenos.back ();
  return ret;
}

int
bracket_check_eof (void)
{
  if (yy_d_bracket > 0) {
    yyerror (strbuf ("Unbalanced brackets at EOF; started at line %d",
       unbalanced_bracket ()));
  }
  return 0;
}

void
push_p3_func ()
{
   nlcount ();
   yy_p3_depth++;
   yy_push_state (P3);
}

void
pop_p3_func (void)
{
  if (yy_p3_depth <= 0) {
    yyerror ("Unbalanced '{%' Pub3 tag at EOF\n");
  } else {
    yy_p3_depth --;
    yy_pop_state ();
  }
}

//-----------------------------------------------------------------------

// P3 perl-style regex's!

void 
p3_regex_begin (char ch) 
{
  yy_p3_regex_start_line = PLINENO;
  char open, close;

  open = ch;
  switch (ch) {
  case '#':
  case '!':
  case '@':
  case '/':
  case '%':
    close = ch;
    break;
  case '{': close = '}'; break;
  case '<': close = '>'; break;
  case '(': close = ')'; break;
  case '[': close = ']'; break;
  default:
    yyerror (strbuf ("unexpected P3 regex delimiter: '%c'\n", ch));
    break;
  }

  yy_p3_regex_close_char = close;
  yy_p3_regex_open_char = open;
  yy_push_state (P3_REGEX);
}

int  
p3_regex_is_close_char (char c) 
{
  return c == yy_p3_regex_close_char;
}

void 
p3_regex_add (const char *in) 
{
   yy_p3_regex_buf.cat (in, true);
}

void
p3_regex_escape_sequence (const char *in)
{
  // if the char being escape is exactly the close sequence, or
  // the escape character, then strip off the escape!
  if (in[1] == yy_p3_regex_close_char || in[1] == '\\') { in++; }
  p3_regex_add (in);
}

int  
p3_regex_bad_eof () 
{
  yyerror (strbuf ("Found EOF when looking for end of regex, "
           "started on line %d\n", yy_p3_regex_start_line));
  return -1;
}

int
p3_regex_finish (const char *opts) 
{
  yylval.regex.regex = yy_p3_regex_buf;
  yylval.regex.opts = opts;
  yy_pop_state ();
  yy_p3_regex_buf.tosuio ()->clear ();
  return T_P3_REGEX;
}

//-----------------------------------------------------------------------


/*
// States:
//   STR - string within an HTML tag or within regular mode
//   SSTR - string with single quotes around it
//   H - HTML w/ includes and variables and switches and such
//   HTAG - Regular tag within HTML mode
//   PTAG - Pub tag within HTML
//   PSTR - Parsed string
//   PVAR - Variable state (within ${...})
//   WH - White-space-stripped HTML
//   HCOM - HTML Comment
//   JS - JavaScript
//   TXLCOM - Translator comment
//   TXLCOM3 - Translator comment state 3
//   POUND_REGEX - m#...# regex environment
//   P3 -- Pub v3 (expanded boolean logic)
//
*/
