/* YACC parser for C++ names, for GDB.

   Copyright 2003, 2004
   Free Software Foundation, Inc.

   Parts of the lexer are based on c-exp.y from GDB.

This file is part of GDB.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  */

/* Note that malloc's and realloc's in this file are transformed to
   xmalloc and xrealloc respectively by the same sed command in the
   makefile that remaps any other malloc/realloc inserted by the parser
   generator.  Doing this with #defines and trying to control the interaction
   with include files (<malloc.h> and <stdlib.h> for example) just became
   too messy, particularly when such includes can be inserted at random
   times by the parser generator.  */

%{

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#include "safe-ctype.h"
#include "libiberty.h"
#include "demangle.h"

#define IN_GDB
#include "cp-demangle.h"

#include "cp-names.h"

static const char *lexptr, *prev_lexptr;

static struct d_comp *d_qualify (struct d_comp *, int, int);

static struct d_comp *d_int_type (int);

static struct d_comp *d_op_from_string (const char *opname);

static struct d_comp *d_unary (const char *opname, struct d_comp *);
static struct d_comp *d_binary (const char *opname, struct d_comp *, struct d_comp *);

static const char *symbol_end (const char *lexptr);

/* Global state, ew.  */
struct d_info *di;
static struct d_comp *result;

/* Ew ew, ew ew, ew ew ew.  */
#define error printf

#define HOST_CHAR_BIT 8
#define NORETURN

#undef TARGET_INT_BIT
#define TARGET_INT_BIT 32

#undef TARGET_LONG_BIT
#define TARGET_LONG_BIT 32

#undef TARGET_LONG_LONG_BIT
#define TARGET_LONG_LONG_BIT 64

#define QUAL_CONST 1
#define QUAL_RESTRICT 2
#define QUAL_VOLATILE 4

#define INT_CHAR	(1 << 0)
#define INT_SHORT	(1 << 1)
#define INT_LONG	(1 << 2)
#define INT_LLONG	(1 << 3)

#define INT_SIGNED	(1 << 4)
#define INT_UNSIGNED	(1 << 5)

#define BINOP_ADD 1
#define BINOP_RSH 2
#define BINOP_LSH 3
#define BINOP_SUB 4
#define BINOP_MUL 5
#define BINOP_DIV 6
#define BINOP_REM 7
#define BINOP_BITWISE_IOR 8
#define BINOP_BITWISE_AND 9
#define BINOP_BITWISE_XOR 10
#define BINOP_END 11

/* Remap normal yacc parser interface names (yyparse, yylex, yyerror, etc),
   as well as gratuitiously global symbol names, so we can have multiple
   yacc generated parsers in gdb.  Note that these are only the variables
   produced by yacc.  If other parser generators (bison, byacc, etc) produce
   additional global names that conflict at link time, then those parser
   generators need to be fixed instead of adding those names to this list. */

#define	yymaxdepth cpname_maxdepth
#define	yyparse	cpname_parse
#define	yylex	cpname_lex
#define	yyerror	cpname_error
#define	yylval	cpname_lval
#define	yychar	cpname_char
#define	yydebug	cpname_debug
#define	yypact	cpname_pact	
#define	yyr1	cpname_r1			
#define	yyr2	cpname_r2			
#define	yydef	cpname_def		
#define	yychk	cpname_chk		
#define	yypgo	cpname_pgo		
#define	yyact	cpname_act		
#define	yyexca	cpname_exca
#define yyerrflag cpname_errflag
#define yynerrs	cpname_nerrs
#define	yyps	cpname_ps
#define	yypv	cpname_pv
#define	yys	cpname_s
#define	yy_yys	cpname_yys
#define	yystate	cpname_state
#define	yytmp	cpname_tmp
#define	yyv	cpname_v
#define	yy_yyv	cpname_yyv
#define	yyval	cpname_val
#define	yylloc	cpname_lloc
#define yyreds	cpname_reds		/* With YYDEBUG defined */
#define yytoks	cpname_toks		/* With YYDEBUG defined */
#define yyname	cpname_name		/* With YYDEBUG defined */
#define yyrule	cpname_rule		/* With YYDEBUG defined */
#define yylhs	cpname_yylhs
#define yylen	cpname_yylen
#define yydefred cpname_yydefred
#define yydgoto	cpname_yydgoto
#define yysindex cpname_yysindex
#define yyrindex cpname_yyrindex
#define yygindex cpname_yygindex
#define yytable	 cpname_yytable
#define yycheck	 cpname_yycheck

#ifndef YYDEBUG
#define	YYDEBUG 1		/* Default to yydebug support */
#endif

int yyparse (void);

static int yylex (void);

void yyerror (char *);

%}

/* Although the yacc "value" of an expression is not used,
   since the result is stored in the structure being created,
   other node types do have values.  */

%union
  {
    struct d_comp *comp;
    struct nested {
      struct d_comp *comp;
      struct d_comp **last;
    } nested;
    struct {
      struct d_comp *comp, *last;
    } nested1;
    struct {
      struct d_comp *comp, **last;
      struct nested fn;
      struct d_comp *start;
      int fold_flag;
    } abstract;
    int lval;
    struct {
      int val;
      struct d_comp *type;
    } typed_val_int;
    const char *opname;
  }

%{
/* YYSTYPE gets defined by %union */
static int parse_number (const char *, int, int, YYSTYPE *);
%}

%type <comp> exp exp1 type start start_opt operator colon_name
%type <comp> unqualified_name colon_ext_name
%type <comp> template template_arg
%type <comp> builtin_type
%type <comp> typespec_2 array_indicator
%type <comp> colon_ext_only ext_only_name

%type <comp> demangler_special function conversion_op
%type <nested> conversion_op_name

%type <abstract> abstract_declarator direct_abstract_declarator
%type <abstract> abstract_declarator_fn
%type <nested> declarator direct_declarator function_arglist

%type <nested> declarator_1 direct_declarator_1

%type <nested> template_params function_args
%type <nested> ptr_operator

%type <nested1> nested_name

%type <lval> qualifier qualifiers qualifiers_opt

%type <lval> int_part int_seq

%token <comp> INT
%token <comp> FLOAT

%token <comp> NAME
%type <comp> name

%token STRUCT CLASS UNION ENUM SIZEOF UNSIGNED COLONCOLON
%token TEMPLATE
%token ERROR
%token NEW DELETE OPERATOR
%token STATIC_CAST REINTERPRET_CAST DYNAMIC_CAST

/* Special type cases, put in to allow the parser to distinguish different
   legal basetypes.  */
%token SIGNED_KEYWORD LONG SHORT INT_KEYWORD CONST_KEYWORD VOLATILE_KEYWORD DOUBLE_KEYWORD BOOL
%token ELLIPSIS RESTRICT VOID FLOAT_KEYWORD CHAR WCHAR_T

%token <opname> ASSIGN_MODIFY

/* C++ */
%token TRUEKEYWORD
%token FALSEKEYWORD

/* Non-C++ things we get from the demangler.  */
%token <lval> DEMANGLER_SPECIAL
%token CONSTRUCTION_VTABLE CONSTRUCTION_IN
%token <typed_val_int> GLOBAL

%{
enum {
  GLOBAL_CONSTRUCTORS = D_COMP_LITERAL + 20,
  GLOBAL_DESTRUCTORS = D_COMP_LITERAL + 21
};
%}

/* Precedence declarations.  */

/* Give NAME lower precedence than COLONCOLON, so that nested_name will
   associate greedily.  */
%nonassoc NAME

/* Give NEW and DELETE higher precedence than '[', because we can not
   have an array of type operator new.  */
%nonassoc NEW DELETE

%left ','
%right '=' ASSIGN_MODIFY
%right '?'
%left OROR
%left ANDAND
%left '|'
%left '^'
%left '&'
%left EQUAL NOTEQUAL
%left '<' '>' LEQ GEQ
%left LSH RSH
%left '@'
%left '+' '-'
%left '*' '/' '%'
%right UNARY INCREMENT DECREMENT

/* We don't need a precedence for '(' in this reduced grammar, and it
   can mask some unpleasant bugs, so disable it for now.  */

%right ARROW '.' '[' /* '(' */
%left COLONCOLON


%%

result		:	start
			{ result = $1; }
		;

start		:	type

		|	demangler_special

		|	function

		;

start_opt	:	/* */
			{ $$ = NULL; }
		|	COLONCOLON start
			{ $$ = $2; }
		;

function
		/* Function with a return type.  declarator_1 is used to prevent
		   ambiguity with the next rule.  */
		:	typespec_2 declarator_1
			{ $$ = $2.comp;
			  *$2.last = $1;
			}

		/* Function without a return type.  We need to use typespec_2
		   to prevent conflicts from qualifiers_opt - harmless.  The
		   start_opt is used to handle "function-local" variables and
		   types.  */
		|	typespec_2 function_arglist start_opt
			{ $$ = cp_v3_d_make_comp (di, D_COMP_TYPED_NAME, $1, $2.comp);
			  if ($3) $$ = cp_v3_d_make_comp (di, D_COMP_LOCAL_NAME, $$, $3); }
		|	colon_ext_only function_arglist start_opt
			{ $$ = cp_v3_d_make_comp (di, D_COMP_TYPED_NAME, $1, $2.comp);
			  if ($3) $$ = cp_v3_d_make_comp (di, D_COMP_LOCAL_NAME, $$, $3); }

		|	conversion_op_name start_opt
			{ $$ = $1.comp;
			  if ($2) $$ = cp_v3_d_make_comp (di, D_COMP_LOCAL_NAME, $$, $2); }
		|	conversion_op_name abstract_declarator_fn
			{ if ($2.last)
			    {
			       /* First complete the abstract_declarator's type using
				  the typespec from the conversion_op_name.  */
			      *$2.last = *$1.last;
			      /* Then complete the conversion_op_name with the type.  */
			      *$1.last = $2.comp;
			    }
			  /* If we have an arglist, build a function type.  */
			  if ($2.fn.comp)
			    $$ = cp_v3_d_make_comp (di, D_COMP_TYPED_NAME, $1.comp, $2.fn.comp);
			  else
			    $$ = $1.comp;
			  if ($2.start) $$ = cp_v3_d_make_comp (di, D_COMP_LOCAL_NAME, $$, $2.start);
			}
		;

demangler_special
		:	DEMANGLER_SPECIAL start
			{ $$ = cp_v3_d_make_empty (di, $1);
			  d_left ($$) = $2;
			  d_right ($$) = NULL; }
		|	CONSTRUCTION_VTABLE start CONSTRUCTION_IN start
			{ $$ = cp_v3_d_make_comp (di, D_COMP_CONSTRUCTION_VTABLE, $2, $4); }
		|	GLOBAL
			{ $$ = cp_v3_d_make_empty (di, $1.val);
			  d_left ($$) = $1.type;
			  d_right ($$) = NULL; }
		;

operator	:	OPERATOR NEW
			{ $$ = cp_v3_d_make_operator_from_string (di, "new"); }
		|	OPERATOR DELETE
			{ $$ = cp_v3_d_make_operator_from_string (di, "delete"); }
		|	OPERATOR NEW '[' ']'
			{ $$ = cp_v3_d_make_operator_from_string (di, "new[]"); }
		|	OPERATOR DELETE '[' ']'
			{ $$ = cp_v3_d_make_operator_from_string (di, "delete[]"); }
		|	OPERATOR '+'
			{ $$ = cp_v3_d_make_operator_from_string (di, "+"); }
		|	OPERATOR '-'
			{ $$ = cp_v3_d_make_operator_from_string (di, "-"); }
		|	OPERATOR '*'
			{ $$ = cp_v3_d_make_operator_from_string (di, "*"); }
		|	OPERATOR '/'
			{ $$ = cp_v3_d_make_operator_from_string (di, "/"); }
		|	OPERATOR '%'
			{ $$ = cp_v3_d_make_operator_from_string (di, "%"); }
		|	OPERATOR '^'
			{ $$ = cp_v3_d_make_operator_from_string (di, "^"); }
		|	OPERATOR '&'
			{ $$ = cp_v3_d_make_operator_from_string (di, "&"); }
		|	OPERATOR '|'
			{ $$ = cp_v3_d_make_operator_from_string (di, "|"); }
		|	OPERATOR '~'
			{ $$ = cp_v3_d_make_operator_from_string (di, "~"); }
		|	OPERATOR '!'
			{ $$ = cp_v3_d_make_operator_from_string (di, "!"); }
		|	OPERATOR '='
			{ $$ = cp_v3_d_make_operator_from_string (di, "="); }
		|	OPERATOR '<'
			{ $$ = cp_v3_d_make_operator_from_string (di, "<"); }
		|	OPERATOR '>'
			{ $$ = cp_v3_d_make_operator_from_string (di, ">"); }
		|	OPERATOR ASSIGN_MODIFY
			{ $$ = cp_v3_d_make_operator_from_string (di, $2); }
		|	OPERATOR LSH
			{ $$ = cp_v3_d_make_operator_from_string (di, "<<"); }
		|	OPERATOR RSH
			{ $$ = cp_v3_d_make_operator_from_string (di, ">>"); }
		|	OPERATOR EQUAL
			{ $$ = cp_v3_d_make_operator_from_string (di, "=="); }
		|	OPERATOR NOTEQUAL
			{ $$ = cp_v3_d_make_operator_from_string (di, "!="); }
		|	OPERATOR LEQ
			{ $$ = cp_v3_d_make_operator_from_string (di, "<="); }
		|	OPERATOR GEQ
			{ $$ = cp_v3_d_make_operator_from_string (di, ">="); }
		|	OPERATOR ANDAND
			{ $$ = cp_v3_d_make_operator_from_string (di, "&&"); }
		|	OPERATOR OROR
			{ $$ = cp_v3_d_make_operator_from_string (di, "||"); }
		|	OPERATOR INCREMENT
			{ $$ = cp_v3_d_make_operator_from_string (di, "++"); }
		|	OPERATOR DECREMENT
			{ $$ = cp_v3_d_make_operator_from_string (di, "--"); }
		|	OPERATOR ','
			{ $$ = cp_v3_d_make_operator_from_string (di, ","); }
		|	OPERATOR ARROW '*'
			{ $$ = cp_v3_d_make_operator_from_string (di, "->*"); }
		|	OPERATOR ARROW
			{ $$ = cp_v3_d_make_operator_from_string (di, "->"); }
		|	OPERATOR '(' ')'
			{ $$ = cp_v3_d_make_operator_from_string (di, "()"); }
		|	OPERATOR '[' ']'
			{ $$ = cp_v3_d_make_operator_from_string (di, "[]"); }
		;

		/* Conversion operators.  We don't try to handle some of
		   the wackier demangler output for function pointers,
		   since it's not clear that it's parseable.  */
conversion_op
		:	OPERATOR typespec_2
			{ $$ = cp_v3_d_make_comp (di, D_COMP_CAST, $2, NULL); }
		;

conversion_op_name
		:	nested_name conversion_op
			{ $$.comp = $1.comp;
			  d_right ($1.last) = $2;
			  $$.last = &d_left ($2);
			}
		|	conversion_op
			{ $$.comp = $1;
			  $$.last = &d_left ($1);
			}
		|	COLONCOLON nested_name conversion_op
			{ $$.comp = $2.comp;
			  d_right ($2.last) = $3;
			  $$.last = &d_left ($3);
			}
		|	COLONCOLON conversion_op
			{ $$.comp = $2;
			  $$.last = &d_left ($2);
			}
		;

/* D_COMP_NAME */
/* This accepts certain invalid placements of '~'.  */
unqualified_name:	operator
		|	operator '<' template_params '>'
			{ $$ = cp_v3_d_make_comp (di, D_COMP_TEMPLATE, $1, $3.comp); }
		|	'~' NAME
			{ $$ = cp_v3_d_make_dtor (di, gnu_v3_complete_object_dtor, $2); }
		;

/* This rule is used in name and nested_name, and expanded inline there
   for efficiency.  */
/*
scope_id	:	NAME
		|	template
		;
*/

colon_name	:	name
		|	COLONCOLON name
			{ $$ = $2; }
		;

/* D_COMP_QUAL_NAME */
/* D_COMP_CTOR / D_COMP_DTOR ? */
name		:	nested_name NAME %prec NAME
			{ $$ = $1.comp; d_right ($1.last) = $2; }
		|	NAME %prec NAME
		|	nested_name template %prec NAME
			{ $$ = $1.comp; d_right ($1.last) = $2; }
		|	template %prec NAME
		;

colon_ext_name	:	colon_name
		|	colon_ext_only
		;

colon_ext_only	:	ext_only_name
		|	COLONCOLON ext_only_name
			{ $$ = $2; }
		;

ext_only_name	:	nested_name unqualified_name
			{ $$ = $1.comp; d_right ($1.last) = $2; }
		|	unqualified_name
		;

nested_name	:	NAME COLONCOLON
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_QUAL_NAME);
			  d_left ($$.comp) = $1;
			  d_right ($$.comp) = NULL;
			  $$.last = $$.comp;
			}
		|	nested_name NAME COLONCOLON
			{ $$.comp = $1.comp;
			  d_right ($1.last) = cp_v3_d_make_empty (di, D_COMP_QUAL_NAME);
			  $$.last = d_right ($1.last);
			  d_left ($$.last) = $2;
			  d_right ($$.last) = NULL;
			}
		|	template COLONCOLON
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_QUAL_NAME);
			  d_left ($$.comp) = $1;
			  d_right ($$.comp) = NULL;
			  $$.last = $$.comp;
			}
		|	nested_name template COLONCOLON
			{ $$.comp = $1.comp;
			  d_right ($1.last) = cp_v3_d_make_empty (di, D_COMP_QUAL_NAME);
			  $$.last = d_right ($1.last);
			  d_left ($$.last) = $2;
			  d_right ($$.last) = NULL;
			}
		;

/* D_COMP_TEMPLATE */
/* D_COMP_TEMPLATE_ARGLIST */
template	:	NAME '<' template_params '>'
			{ $$ = cp_v3_d_make_comp (di, D_COMP_TEMPLATE, $1, $3.comp); }
		;

template_params	:	template_arg
			{ $$.comp = cp_v3_d_make_comp (di, D_COMP_TEMPLATE_ARGLIST, $1, NULL);
			$$.last = &d_right ($$.comp); }
		|	template_params ',' template_arg
			{ $$.comp = $1.comp;
			  *$1.last = cp_v3_d_make_comp (di, D_COMP_TEMPLATE_ARGLIST, $3, NULL);
			  $$.last = &d_right (*$1.last);
			}
		;

/* "type" is inlined into template_arg and function_args.  */

/* Also an integral constant-expression of integral type, and a
   pointer to member (?) */
template_arg	:	typespec_2
		|	typespec_2 abstract_declarator
			{ $$ = $2.comp;
			  *$2.last = $1;
			}
		|	'&' start
			{ $$ = cp_v3_d_make_comp (di, D_COMP_UNARY, cp_v3_d_make_operator_from_string (di, "&"), $2); }
		|	'&' '(' start ')'
			{ $$ = cp_v3_d_make_comp (di, D_COMP_UNARY, cp_v3_d_make_operator_from_string (di, "&"), $3); }
		|	exp
		;

function_args	:	typespec_2
			{ if ($1->type == D_COMP_BUILTIN_TYPE
			      && $1->u.s_builtin.type->print == D_PRINT_VOID)
			    {
			      $$.comp = NULL;
			      $$.last = &$$.comp;
			    }
			  else
			    {
			      $$.comp = cp_v3_d_make_comp (di, D_COMP_ARGLIST, $1, NULL);
			      $$.last = &d_right ($$.comp);
			    }
			}
		|	typespec_2 abstract_declarator
			{ *$2.last = $1;
			  $$.comp = cp_v3_d_make_comp (di, D_COMP_ARGLIST, $2.comp, NULL);
			  $$.last = &d_right ($$.comp);
			}
		|	function_args ',' typespec_2
			{ *$1.last = cp_v3_d_make_comp (di, D_COMP_ARGLIST, $3, NULL);
			  $$.comp = $1.comp;
			  $$.last = &d_right (*$1.last);
			}
		|	function_args ',' typespec_2 abstract_declarator
			{ *$4.last = $3;
			  *$1.last = cp_v3_d_make_comp (di, D_COMP_ARGLIST, $4.comp, NULL);
			  $$.comp = $1.comp;
			  $$.last = &d_right (*$1.last);
			}
		|	function_args ',' ELLIPSIS
			{ *$1.last
			    = cp_v3_d_make_comp (di, D_COMP_ARGLIST,
					   cp_v3_d_make_builtin_type (di, 'z'),
					   NULL);
			  $$.comp = $1.comp;
			  $$.last = &d_right (*$1.last);
			}
		;

function_arglist:	'(' function_args ')' qualifiers_opt
			{ $$.comp = cp_v3_d_make_comp (di, D_COMP_FUNCTION_TYPE, NULL, $2.comp);
			  $$.last = &d_left ($$.comp);
			  $$.comp = d_qualify ($$.comp, $4, 1); }
		|	'(' ')' qualifiers_opt
			{ $$.comp = cp_v3_d_make_comp (di, D_COMP_FUNCTION_TYPE, NULL, NULL);
			  $$.last = &d_left ($$.comp);
			  $$.comp = d_qualify ($$.comp, $3, 1); }
		;

/* Should do something about D_COMP_VENDOR_TYPE_QUAL */
qualifiers_opt	:	/* epsilon */
			{ $$ = 0; }
		|	qualifiers
		;

qualifier	:	RESTRICT
			{ $$ = QUAL_RESTRICT; }
		|	VOLATILE_KEYWORD
			{ $$ = QUAL_VOLATILE; }
		|	CONST_KEYWORD
			{ $$ = QUAL_CONST; }
		;

qualifiers	:	qualifier
		|	qualifier qualifiers
			{ $$ = $1 | $2; }
		;

/* This accepts all sorts of invalid constructions and produces
   invalid output for them - an error would be better.  */

int_part	:	INT_KEYWORD
			{ $$ = 0; }
		|	SIGNED_KEYWORD
			{ $$ = INT_SIGNED; }
		|	UNSIGNED
			{ $$ = INT_UNSIGNED; }
		|	CHAR
			{ $$ = INT_CHAR; }
		|	LONG
			{ $$ = INT_LONG; }
		|	SHORT
			{ $$ = INT_SHORT; }
		;

int_seq		:	int_part
		|	int_seq int_part
			{ $$ = $1 | $2; if ($1 & $2 & INT_LONG) $$ = $1 | INT_LLONG; }
		;

builtin_type	:	int_seq
			{ $$ = d_int_type ($1); }
		|	FLOAT_KEYWORD
			{ $$ = cp_v3_d_make_builtin_type (di, 'f'); }
		|	DOUBLE_KEYWORD
			{ $$ = cp_v3_d_make_builtin_type (di, 'd'); }
		|	LONG DOUBLE_KEYWORD
			{ $$ = cp_v3_d_make_builtin_type (di, 'e'); }
		|	BOOL
			{ $$ = cp_v3_d_make_builtin_type (di, 'b'); }
		|	WCHAR_T
			{ $$ = cp_v3_d_make_builtin_type (di, 'w'); }
		|	VOID
			{ $$ = cp_v3_d_make_builtin_type (di, 'v'); }
		;

ptr_operator	:	'*' qualifiers_opt
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_POINTER);
			  $$.comp->u.s_binary.left = $$.comp->u.s_binary.right = NULL;
			  $$.last = &d_left ($$.comp);
			  $$.comp = d_qualify ($$.comp, $2, 0); }
		/* g++ seems to allow qualifiers after the reference?  */
		|	'&'
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_REFERENCE);
			  $$.comp->u.s_binary.left = $$.comp->u.s_binary.right = NULL;
			  $$.last = &d_left ($$.comp); }
		|	nested_name '*' qualifiers_opt
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_PTRMEM_TYPE);
			  $$.comp->u.s_binary.left = $1.comp;
			  /* Convert the innermost D_COMP_QUAL_NAME to a D_COMP_NAME.  */
			  *$1.last = *d_left ($1.last);
			  $$.comp->u.s_binary.right = NULL;
			  $$.last = &d_right ($$.comp);
			  $$.comp = d_qualify ($$.comp, $3, 0); }
		|	COLONCOLON nested_name '*' qualifiers_opt
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_PTRMEM_TYPE);
			  $$.comp->u.s_binary.left = $2.comp;
			  /* Convert the innermost D_COMP_QUAL_NAME to a D_COMP_NAME.  */
			  *$2.last = *d_left ($2.last);
			  $$.comp->u.s_binary.right = NULL;
			  $$.last = &d_right ($$.comp);
			  $$.comp = d_qualify ($$.comp, $4, 0); }
		;

array_indicator	:	'[' ']'
			{ $$ = cp_v3_d_make_empty (di, D_COMP_ARRAY_TYPE);
			  d_left ($$) = NULL;
			}
		|	'[' INT ']'
			{ $$ = cp_v3_d_make_empty (di, D_COMP_ARRAY_TYPE);
			  d_left ($$) = $2;
			}
		;

/* Details of this approach inspired by the G++ < 3.4 parser.  */

/* This rule is only used in typespec_2, and expanded inline there for
   efficiency.  */
/*
typespec	:	builtin_type
		|	colon_name
		;
*/

typespec_2	:	builtin_type qualifiers
			{ $$ = d_qualify ($1, $2, 0); }
		|	builtin_type
		|	qualifiers builtin_type qualifiers
			{ $$ = d_qualify ($2, $1 | $3, 0); }
		|	qualifiers builtin_type
			{ $$ = d_qualify ($2, $1, 0); }

		|	name qualifiers
			{ $$ = d_qualify ($1, $2, 0); }
		|	name
		|	qualifiers name qualifiers
			{ $$ = d_qualify ($2, $1 | $3, 0); }
		|	qualifiers name
			{ $$ = d_qualify ($2, $1, 0); }

		|	COLONCOLON name qualifiers
			{ $$ = d_qualify ($2, $3, 0); }
		|	COLONCOLON name
			{ $$ = $2; }
		|	qualifiers COLONCOLON name qualifiers
			{ $$ = d_qualify ($3, $1 | $4, 0); }
		|	qualifiers COLONCOLON name
			{ $$ = d_qualify ($3, $1, 0); }
		;

abstract_declarator
		:	ptr_operator
			{ $$.comp = $1.comp; $$.last = $1.last;
			  $$.fn.comp = NULL; $$.fn.last = NULL; }
		|	ptr_operator abstract_declarator
			{ $$ = $2; $$.fn.comp = NULL; $$.fn.last = NULL;
			  if ($2.fn.comp) { $$.last = $2.fn.last; *$2.last = $2.fn.comp; }
			  *$$.last = $1.comp;
			  $$.last = $1.last; }
		|	direct_abstract_declarator
			{ $$.fn.comp = NULL; $$.fn.last = NULL;
			  if ($1.fn.comp) { $$.last = $1.fn.last; *$1.last = $1.fn.comp; }
			}
		;

direct_abstract_declarator
		:	'(' abstract_declarator ')'
			{ $$ = $2; $$.fn.comp = NULL; $$.fn.last = NULL; $$.fold_flag = 1;
			  if ($2.fn.comp) { $$.last = $2.fn.last; *$2.last = $2.fn.comp; }
			}
		|	direct_abstract_declarator function_arglist
			{ $$.fold_flag = 0;
			  if ($1.fn.comp) { $$.last = $1.fn.last; *$1.last = $1.fn.comp; }
			  if ($1.fold_flag)
			    {
			      *$$.last = $2.comp;
			      $$.last = $2.last;
			    }
			  else
			    $$.fn = $2;
			}
		|	direct_abstract_declarator array_indicator
			{ $$.fn.comp = NULL; $$.fn.last = NULL; $$.fold_flag = 0;
			  if ($1.fn.comp) { $$.last = $1.fn.last; *$1.last = $1.fn.comp; }
			  *$1.last = $2;
			  $$.last = &d_right ($2);
			}
		|	array_indicator
			{ $$.fn.comp = NULL; $$.fn.last = NULL; $$.fold_flag = 0;
			  $$.comp = $1;
			  $$.last = &d_right ($1);
			}
		/* G++ has the following except for () and (type).  Then
		   (type) is handled in regcast_or_absdcl and () is handled
		   in fcast_or_absdcl.  */
		/* However, this is only useful for function types, and
		   generates reduce/reduce conflicts with direct_declarators.
		   We're interested in pointer-to-function types, and in
		   functions, but not in function types - so leave this
		   out.  */
		/* |	function_arglist */
		;

abstract_declarator_fn
		:	ptr_operator
			{ $$.comp = $1.comp; $$.last = $1.last;
			  $$.fn.comp = NULL; $$.fn.last = NULL; $$.start = NULL; }
		|	ptr_operator abstract_declarator_fn
			{ $$ = $2;
			  if ($2.last)
			    *$$.last = $1.comp;
			  else
			    $$.comp = $1.comp;
			  $$.last = $1.last;
			}
		|	direct_abstract_declarator
			{ $$.comp = $1.comp; $$.last = $1.last; $$.fn = $1.fn; $$.start = NULL; }
		|	direct_abstract_declarator function_arglist COLONCOLON start
			{ $$.start = $4;
			  if ($1.fn.comp) { $$.last = $1.fn.last; *$1.last = $1.fn.comp; }
			  if ($1.fold_flag)
			    {
			      *$$.last = $2.comp;
			      $$.last = $2.last;
			    }
			  else
			    $$.fn = $2;
			}
		|	function_arglist start_opt
			{ $$.fn = $1;
			  $$.start = $2;
			  $$.comp = NULL; $$.last = NULL;
			}
		;

type		:	typespec_2
		|	typespec_2 abstract_declarator
			{ $$ = $2.comp;
			  *$2.last = $1;
			}
		;

declarator	:	ptr_operator declarator
			{ $$.comp = $2.comp;
			  $$.last = $1.last;
			  *$2.last = $1.comp; }
		|	direct_declarator
		;

direct_declarator
		:	'(' declarator ')'
			{ $$ = $2; }
		|	direct_declarator function_arglist
			{ $$.comp = $1.comp;
			  *$1.last = $2.comp;
			  $$.last = $2.last;
			}
		|	direct_declarator array_indicator
			{ $$.comp = $1.comp;
			  *$1.last = $2;
			  $$.last = &d_right ($2);
			}
		|	colon_ext_name
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_TYPED_NAME);
			  d_left ($$.comp) = $1;
			  $$.last = &d_right ($$.comp);
			}
		;

/* These are similar to declarator and direct_declarator except that they
   do not permit ( colon_ext_name ), which is ambiguous with a function
   argument list.  They also don't permit a few other forms with redundant
   parentheses around the colon_ext_name; any colon_ext_name in parentheses
   must be followed by an argument list or an array indicator, or preceded
   by a pointer.  */
declarator_1	:	ptr_operator declarator_1
			{ $$.comp = $2.comp;
			  $$.last = $1.last;
			  *$2.last = $1.comp; }
		|	colon_ext_name
			{ $$.comp = cp_v3_d_make_empty (di, D_COMP_TYPED_NAME);
			  d_left ($$.comp) = $1;
			  $$.last = &d_right ($$.comp);
			}
		|	direct_declarator_1

			/* Function local variable or type.  The typespec to
			   our left is the type of the containing function. 
			   This should be OK, because function local types
			   can not be templates, so the return types of their
			   members will not be mangled.  If they are hopefully
			   they'll end up to the right of the ::.  */
		|	colon_ext_name function_arglist COLONCOLON start
			{ $$.comp = cp_v3_d_make_comp (di, D_COMP_TYPED_NAME, $1, $2.comp);
			  $$.last = $2.last;
			  $$.comp = cp_v3_d_make_comp (di, D_COMP_LOCAL_NAME, $$.comp, $4);
			}
		|	direct_declarator_1 function_arglist COLONCOLON start
			{ $$.comp = $1.comp;
			  *$1.last = $2.comp;
			  $$.last = $2.last;
			  $$.comp = cp_v3_d_make_comp (di, D_COMP_LOCAL_NAME, $$.comp, $4);
			}
		;

direct_declarator_1
		:	'(' ptr_operator declarator ')'
			{ $$.comp = $3.comp;
			  $$.last = $2.last;
			  *$3.last = $2.comp; }
		|	direct_declarator_1 function_arglist
			{ $$.comp = $1.comp;
			  *$1.last = $2.comp;
			  $$.last = $2.last;
			}
		|	direct_declarator_1 array_indicator
			{ $$.comp = $1.comp;
			  *$1.last = $2;
			  $$.last = &d_right ($2);
			}
		|	colon_ext_name function_arglist
			{ $$.comp = cp_v3_d_make_comp (di, D_COMP_TYPED_NAME, $1, $2.comp);
			  $$.last = $2.last;
			}
		|	colon_ext_name array_indicator
			{ $$.comp = cp_v3_d_make_comp (di, D_COMP_TYPED_NAME, $1, $2);
			  $$.last = &d_right ($2);
			}
		;

exp	:	'(' exp1 ')'
		{ $$ = $2; }
	;

/* Silly trick.  Only allow '>' when parenthesized, in order to
   handle conflict with templates.  */
exp1	:	exp
	;

exp1	:	exp '>' exp
		{ $$ = d_binary (">", $1, $3); }
	;

/* Expressions, not including the comma operator.  */
exp	:	'-' exp    %prec UNARY
		{ $$ = d_unary ("-", $2); }
	;

exp	:	'!' exp    %prec UNARY
		{ $$ = d_unary ("!", $2); }
	;

exp	:	'~' exp    %prec UNARY
		{ $$ = d_unary ("~", $2); }
	;

/* Casts.  First your normal C-style cast.  If exp is a LITERAL, just change
   its type.  */

exp	:	'(' type ')' exp  %prec UNARY
		{ if ($4->type == D_COMP_LITERAL
		      || $4->type == D_COMP_LITERAL_NEG)
		    {
		      $$ = $4;
		      d_left ($4) = $2;
		    }
		  else
		    $$ = cp_v3_d_make_comp (di, D_COMP_UNARY,
				      cp_v3_d_make_comp (di, D_COMP_CAST, $2, NULL),
				      $4);
		}
	;

/* Mangling does not differentiate between these, so we don't need to
   either.  */
exp	:	STATIC_CAST '<' type '>' '(' exp1 ')' %prec UNARY
		{ $$ = cp_v3_d_make_comp (di, D_COMP_UNARY,
				    cp_v3_d_make_comp (di, D_COMP_CAST, $3, NULL),
				    $6);
		}
	;

exp	:	DYNAMIC_CAST '<' type '>' '(' exp1 ')' %prec UNARY
		{ $$ = cp_v3_d_make_comp (di, D_COMP_UNARY,
				    cp_v3_d_make_comp (di, D_COMP_CAST, $3, NULL),
				    $6);
		}
	;

exp	:	REINTERPRET_CAST '<' type '>' '(' exp1 ')' %prec UNARY
		{ $$ = cp_v3_d_make_comp (di, D_COMP_UNARY,
				    cp_v3_d_make_comp (di, D_COMP_CAST, $3, NULL),
				    $6);
		}
	;

/* Another form of C++-style cast.  "type ( exp1 )" is not allowed (it's too
   ambiguous), but "name ( exp1 )" is.  Because we don't need to support
   function types, we can handle this unambiguously (the use of typespec_2
   prevents a silly, harmless conflict with qualifiers_opt).  This does not
   appear in demangler output so it's not a great loss if we need to
   disable it.  */
exp	:	typespec_2 '(' exp1 ')' %prec UNARY
		{ $$ = cp_v3_d_make_comp (di, D_COMP_UNARY,
				    cp_v3_d_make_comp (di, D_COMP_CAST, $1, NULL),
				    $3);
		}
	;

/* FIXME ._0 style anonymous names; anonymous namespaces */

/* Binary operators in order of decreasing precedence.  */

exp	:	exp '*' exp
		{ $$ = d_binary ("*", $1, $3); }
	;

exp	:	exp '/' exp
		{ $$ = d_binary ("/", $1, $3); }
	;

exp	:	exp '%' exp
		{ $$ = d_binary ("%", $1, $3); }
	;

exp	:	exp '+' exp
		{ $$ = d_binary ("+", $1, $3); }
	;

exp	:	exp '-' exp
		{ $$ = d_binary ("-", $1, $3); }
	;

exp	:	exp LSH exp
		{ $$ = d_binary ("<<", $1, $3); }
	;

exp	:	exp RSH exp
		{ $$ = d_binary (">>", $1, $3); }
	;

exp	:	exp EQUAL exp
		{ $$ = d_binary ("==", $1, $3); }
	;

exp	:	exp NOTEQUAL exp
		{ $$ = d_binary ("!=", $1, $3); }
	;

exp	:	exp LEQ exp
		{ $$ = d_binary ("<=", $1, $3); }
	;

exp	:	exp GEQ exp
		{ $$ = d_binary (">=", $1, $3); }
	;

exp	:	exp '<' exp
		{ $$ = d_binary ("<", $1, $3); }
	;

exp	:	exp '&' exp
		{ $$ = d_binary ("&", $1, $3); }
	;

exp	:	exp '^' exp
		{ $$ = d_binary ("^", $1, $3); }
	;

exp	:	exp '|' exp
		{ $$ = d_binary ("|", $1, $3); }
	;

exp	:	exp ANDAND exp
		{ $$ = d_binary ("&&", $1, $3); }
	;

exp	:	exp OROR exp
		{ $$ = d_binary ("||", $1, $3); }
	;

/* Not 100% sure these are necessary, but they're harmless.  */
exp	:	exp ARROW NAME
		{ $$ = d_binary ("->", $1, $3); }
	;

exp	:	exp '.' NAME
		{ $$ = d_binary (".", $1, $3); }
	;

exp	:	exp '?' exp ':' exp	%prec '?'
		{ $$ = cp_v3_d_make_comp (di, D_COMP_TRINARY, cp_v3_d_make_operator_from_string (di, "?"),
				    cp_v3_d_make_comp (di, D_COMP_TRINARY_ARG1, $1,
						 cp_v3_d_make_comp (di, D_COMP_TRINARY_ARG2, $3, $5)));
		}
	;
			  
exp	:	INT
	;

/* Not generally allowed.  */
exp	:	FLOAT
	;

exp	:	SIZEOF '(' type ')'	%prec UNARY
		{ $$ = d_unary ("sizeof", $3); }
	;

/* C++.  */
exp     :       TRUEKEYWORD    
		{ struct d_comp *i;
		  i = cp_v3_d_make_name (di, "1", 1);
		  $$ = cp_v3_d_make_comp (di, D_COMP_LITERAL,
				    cp_v3_d_make_builtin_type (di, 'b'),
				    i);
		}
	;

exp     :       FALSEKEYWORD   
		{ struct d_comp *i;
		  i = cp_v3_d_make_name (di, "0", 1);
		  $$ = cp_v3_d_make_comp (di, D_COMP_LITERAL,
				    cp_v3_d_make_builtin_type (di, 'b'),
				    i);
		}
	;

/* end of C++.  */

%%

/* */
struct d_comp *
d_qualify (struct d_comp *lhs, int qualifiers, int is_method)
{
  struct d_comp **inner_p;
  enum d_comp_type type;

  /* For now the order is CONST (innermost), VOLATILE, RESTRICT.  */

#define HANDLE_QUAL(TYPE, MTYPE, QUAL)				\
  if ((qualifiers & QUAL) && (type != TYPE) && (type != MTYPE))	\
    {								\
      *inner_p = cp_v3_d_make_comp (di, is_method ? MTYPE : TYPE,	\
			      *inner_p, NULL);			\
      inner_p = &d_left (*inner_p);				\
      type = (*inner_p)->type;					\
    }								\
  else if (type == TYPE || type == MTYPE)			\
    {								\
      inner_p = &d_left (*inner_p);				\
      type = (*inner_p)->type;					\
    }

  inner_p = &lhs;

  type = (*inner_p)->type;

  HANDLE_QUAL (D_COMP_RESTRICT, D_COMP_RESTRICT_THIS, QUAL_RESTRICT);
  HANDLE_QUAL (D_COMP_VOLATILE, D_COMP_VOLATILE_THIS, QUAL_VOLATILE);
  HANDLE_QUAL (D_COMP_CONST, D_COMP_CONST_THIS, QUAL_CONST);

  return lhs;
}

static struct d_comp *
d_int_type (int flags)
{
  int i;

  switch (flags)
    {
    case INT_SIGNED | INT_CHAR:
      i = 0;
      break;
    case INT_CHAR:
      i = 2;
      break;
    case INT_UNSIGNED | INT_CHAR:
      i = 7;
      break;
    case 0:
    case INT_SIGNED:
      i = 8;
      break;
    case INT_UNSIGNED:
      i = 9;
      break;
    case INT_LONG:
    case INT_SIGNED | INT_LONG:
      i = 11;
      break;
    case INT_UNSIGNED | INT_LONG:
      i = 12;
      break;
    case INT_SHORT:
    case INT_SIGNED | INT_SHORT:
      i = 18;
      break;
    case INT_UNSIGNED | INT_SHORT:
      i = 19;
      break;
    case INT_LLONG | INT_LONG:
    case INT_SIGNED | INT_LLONG | INT_LONG:
      i = 23;
      break;
    case INT_UNSIGNED | INT_LLONG | INT_LONG:
      i = 24;
      break;
    default:
      return NULL;
    }

  return cp_v3_d_make_builtin_type (di, i + 'a');
}

static struct d_comp *
d_unary (const char *name, struct d_comp *lhs)
{
  return cp_v3_d_make_comp (di, D_COMP_UNARY, cp_v3_d_make_operator_from_string (di, name), lhs);
}

static struct d_comp *
d_binary (const char *name, struct d_comp *lhs, struct d_comp *rhs)
{
  return cp_v3_d_make_comp (di, D_COMP_BINARY, cp_v3_d_make_operator_from_string (di, name),
		      cp_v3_d_make_comp (di, D_COMP_BINARY_ARGS, lhs, rhs));
}

static const char *
target_charset (void)
{
  return "foo";
}

static const char *
host_charset (void)
{
  return "bar";
}

/* Take care of parsing a number (anything that starts with a digit).
   Set yylval and return the token type; update lexptr.
   LEN is the number of characters in it.  */

/*** Needs some error checking for the float case ***/

static int
parse_number (const char *p, int len, int parsed_float, YYSTYPE *putithere)
{
  int unsigned_p = 0;

  /* Number of "L" suffixes encountered.  */
  int long_p = 0;

  struct d_comp *signed_type;
  struct d_comp *unsigned_type;
  struct d_comp *type, *name;
  enum d_comp_type literal_type;

  if (p[0] == '-')
    {
      literal_type = D_COMP_LITERAL_NEG;
      p++;
      len--;
    }
  else
    literal_type = D_COMP_LITERAL;

  if (parsed_float)
    {
      /* It's a float since it contains a point or an exponent.  */
      char c;

      /* The GDB lexer checks the result of scanf at this point.  Not doing
         this leaves our error checking slightly weaker but only for invalid
         data.  */

      /* See if it has `f' or `l' suffix (float or long double).  */

      c = TOLOWER (p[len - 1]);

      if (c == 'f')
      	{
      	  len--;
      	  type = cp_v3_d_make_builtin_type (di, 'f');
      	}
      else if (c == 'l')
	{
	  len--;
	  type = cp_v3_d_make_builtin_type (di, 'e');
	}
      else if (ISDIGIT (c) || c == '.')
	type = cp_v3_d_make_builtin_type (di, 'd');
      else
	return ERROR;

      name = cp_v3_d_make_name (di, p, len);
      putithere->comp = cp_v3_d_make_comp (di, literal_type, type, name);

      return FLOAT;
    }

  /* This treats 0x1 and 1 as different literals.  We also do not
     automatically generate unsigned types.  */

  long_p = 0;
  unsigned_p = 0;
  while (len > 0)
    {
      if (p[len - 1] == 'l' || p[len - 1] == 'L')
	{
	  len--;
	  long_p++;
	  continue;
	}
      if (p[len - 1] == 'u' || p[len - 1] == 'U')
	{
	  len--;
	  unsigned_p++;
	  continue;
	}
      break;
    }

  if (long_p == 0)
    {
      unsigned_type = cp_v3_d_make_builtin_type (di, 'j');
      signed_type = cp_v3_d_make_builtin_type (di, 'i');
    }
  else if (long_p == 1)
    {
      unsigned_type = cp_v3_d_make_builtin_type (di, 'm');
      signed_type = cp_v3_d_make_builtin_type (di, 'l');
    }
  else
    {
      unsigned_type = cp_v3_d_make_builtin_type (di, 'x');
      signed_type = cp_v3_d_make_builtin_type (di, 'y');
    }

   /* If the high bit of the worked out type is set then this number
      has to be unsigned. */

   if (unsigned_p)
     type = unsigned_type;
   else
     type = signed_type;

   name = cp_v3_d_make_name (di, p, len);
   putithere->comp = cp_v3_d_make_comp (di, literal_type, type, name);

   return INT;
}

/* Print an error message saying that we couldn't make sense of a
   \^mumble sequence in a string or character constant.  START and END
   indicate a substring of some larger string that contains the
   erroneous backslash sequence, missing the initial backslash.  */
static NORETURN int
no_control_char_error (const char *start, const char *end)
{
  int len = end - start;
  char *copy = alloca (end - start + 1);

  memcpy (copy, start, len);
  copy[len] = '\0';

  error ("There is no control character `\\%s' in the `%s' character set.",
	 copy, target_charset ());
  return 0;
}

static int
target_char_to_control_char (int c, int *ctrl_char)
{
  *ctrl_char = (c & 037);
  return 1;
}

static int
host_char_to_target (int c, int *ctrl_char)
{
  *ctrl_char = c;
  return 1;
}

static char backslashable[] = "abefnrtv";
static char represented[] = "\a\b\e\f\n\r\t\v";

/* Translate the backslash the way we would in the host character set.  */
static int
c_parse_backslash (int host_char, int *target_char)
{
  const char *ix;
  ix = strchr (backslashable, host_char);
  if (! ix)
    return 0;
  else
    *target_char = represented[ix - backslashable];
  return 1;
}

/* Parse a C escape sequence.  STRING_PTR points to a variable
   containing a pointer to the string to parse.  That pointer
   should point to the character after the \.  That pointer
   is updated past the characters we use.  The value of the
   escape sequence is returned.

   A negative value means the sequence \ newline was seen,
   which is supposed to be equivalent to nothing at all.

   If \ is followed by a null character, we return a negative
   value and leave the string pointer pointing at the null character.

   If \ is followed by 000, we return 0 and leave the string pointer
   after the zeros.  A value of 0 does not mean end of string.  */

static int
parse_escape (const char **string_ptr)
{
  int target_char;
  int c = *(*string_ptr)++;
  if (c_parse_backslash (c, &target_char))
    return target_char;
  else
    switch (c)
      {
      case '\n':
	return -2;
      case 0:
	(*string_ptr)--;
	return 0;
      case '^':
	{
	  /* Remember where this escape sequence started, for reporting
	     errors.  */
	  const char *sequence_start_pos = *string_ptr - 1;

	  c = *(*string_ptr)++;

	  if (c == '?')
	    {
	      /* XXXCHARSET: What is `delete' in the host character set?  */
	      c = 0177;

	      if (!host_char_to_target (c, &target_char))
		error ("There is no character corresponding to `Delete' "
		       "in the target character set `%s'.", host_charset ());

	      return target_char;
	    }
	  else if (c == '\\')
	    target_char = parse_escape (string_ptr);
	  else
	    {
	      if (!host_char_to_target (c, &target_char))
		no_control_char_error (sequence_start_pos, *string_ptr);
	    }

	  /* Now target_char is something like `c', and we want to find
	     its control-character equivalent.  */
	  if (!target_char_to_control_char (target_char, &target_char))
	    no_control_char_error (sequence_start_pos, *string_ptr);

	  return target_char;
	}

	/* XXXCHARSET: we need to use isdigit and value-of-digit
	   methods of the host character set here.  */

      case '0':
      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
	{
	  int i = c - '0';
	  int count = 0;
	  while (++count < 3)
	    {
	      c = (**string_ptr);
	      if (c >= '0' && c <= '7')
		{
		  (*string_ptr)++;
		  i *= 8;
		  i += c - '0';
		}
	      else
		{
		  break;
		}
	    }
	  return i;
	}
      default:
	if (!host_char_to_target (c, &target_char))
	  error
	    ("The escape sequence `\%c' is equivalent to plain `%c', which"
	     " has no equivalent\n" "in the `%s' character set.", c, c,
	     target_charset ());
	return target_char;
      }
}

struct token
{
  char *operator;
  int token;
  int opcode;
};

#define HANDLE_SPECIAL(string, comp)				\
  if (strncmp (tokstart, string, sizeof (string) - 1) == 0)	\
    {								\
      lexptr = tokstart + sizeof (string) - 1;			\
      yylval.lval = comp;					\
      return DEMANGLER_SPECIAL;					\
    }

#define HANDLE_TOKEN2(string, token, op)		\
  if (lexptr[1] == string[1])				\
    {							\
      lexptr += 2;					\
      yylval.opname = string;				\
      return token;					\
    }      

#define HANDLE_TOKEN3(string, token, op)		\
  if (lexptr[1] == string[1] && lexptr[2] == string[2])	\
    {							\
      lexptr += 3;					\
      yylval.opname = string;				\
      return token;					\
    }      

/* Read one token, getting characters through lexptr.  */

static int
yylex (void)
{
  int c;
  int namelen;
  const char *tokstart, *tokptr;
  int tempbufindex;
  static char *tempbuf;
  static int tempbufsize;

 retry:
  prev_lexptr = lexptr;
  tokstart = lexptr;

  switch (c = *tokstart)
    {
    case 0:
      return 0;

    case ' ':
    case '\t':
    case '\n':
      lexptr++;
      goto retry;

    case '\'':
      /* We either have a character constant ('0' or '\177' for example)
	 or we have a quoted symbol reference ('foo(int,int)' in C++
	 for example). */
      lexptr++;
      c = *lexptr++;
      if (c == '\\')
	c = parse_escape (&lexptr);
      else if (c == '\'')
	error ("Empty character constant.");
      else if (! host_char_to_target (c, &c))
        {
          int toklen = lexptr - tokstart + 1;
          char *tok = alloca (toklen + 1);
          memcpy (tok, tokstart, toklen);
          tok[toklen] = '\0';
          error ("There is no character corresponding to %s in the target "
                 "character set `%s'.", tok, target_charset ());
        }

      c = *lexptr++;
      if (c != '\'')
	error ("Invalid character constant.");

      /* FIXME: We should refer to a canonical form of the character,
	 presumably the same one that appears in manglings - the decimal
	 representation.  But if that isn't in our input then we have to
	 allocate memory for it somewhere.  */
      yylval.comp = cp_v3_d_make_comp (di, D_COMP_LITERAL,
				 cp_v3_d_make_builtin_type (di, 'c'),
				 cp_v3_d_make_name (di, tokstart, lexptr - tokstart));

      return INT;

    case '(':
      if (strncmp (tokstart, "(anonymous namespace)", 21) == 0)
	{
	  lexptr += 21;
	  yylval.comp = cp_v3_d_make_name (di, "(anonymous namespace)",
				     sizeof "(anonymous namespace)" - 1);
	  return NAME;
	}
	/* FALL THROUGH */

    case ')':
    case ',':
      lexptr++;
      return c;

    case '.':
      if (lexptr[1] == '.' && lexptr[2] == '.')
	{
	  lexptr += 3;
	  return ELLIPSIS;
	}

      /* Might be a floating point number.  */
      if (lexptr[1] < '0' || lexptr[1] > '9')
	goto symbol;		/* Nope, must be a symbol. */

      goto try_number;

    case '-':
      HANDLE_TOKEN2 ("-=", ASSIGN_MODIFY, BINOP_SUB);
      HANDLE_TOKEN2 ("--", DECREMENT, BINOP_END);
      HANDLE_TOKEN2 ("->", ARROW, BINOP_END);

      /* For construction vtables.  This is kind of hokey.  */
      if (strncmp (tokstart, "-in-", 4) == 0)
	{
	  lexptr += 4;
	  return CONSTRUCTION_IN;
	}

      if (lexptr[1] < '0' || lexptr[1] > '9')
	{
	  lexptr++;
	  return '-';
	}
      /* FALL THRU into number case.  */

    try_number:
    case '0':
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
      {
	/* It's a number.  */
	int got_dot = 0, got_e = 0, toktype;
	const char *p = tokstart;
	int hex = 0;

	if (c == '-')
	  p++;

	if (c == '0' && (p[1] == 'x' || p[1] == 'X'))
	  {
	    p += 2;
	    hex = 1;
	  }
	else if (c == '0' && (p[1]=='t' || p[1]=='T' || p[1]=='d' || p[1]=='D'))
	  {
	    p += 2;
	    hex = 0;
	  }

	for (;; ++p)
	  {
	    /* This test includes !hex because 'e' is a valid hex digit
	       and thus does not indicate a floating point number when
	       the radix is hex.  */
	    if (!hex && !got_e && (*p == 'e' || *p == 'E'))
	      got_dot = got_e = 1;
	    /* This test does not include !hex, because a '.' always indicates
	       a decimal floating point number regardless of the radix.  */
	    /* drow: Is that true in C99? */
	    else if (!got_dot && *p == '.')
	      got_dot = 1;
	    else if (got_e && (p[-1] == 'e' || p[-1] == 'E')
		     && (*p == '-' || *p == '+'))
	      /* This is the sign of the exponent, not the end of the
		 number.  */
	      continue;
	    /* We will take any letters or digits.  parse_number will
	       complain if past the radix, or if L or U are not final.  */
	    else if (! ISALNUM (*p))
	      break;
	  }
	toktype = parse_number (tokstart, p - tokstart, got_dot|got_e, &yylval);
        if (toktype == ERROR)
	  {
	    char *err_copy = (char *) alloca (p - tokstart + 1);

	    memcpy (err_copy, tokstart, p - tokstart);
	    err_copy[p - tokstart] = 0;
	    error ("Invalid number \"%s\".", err_copy);
	    return ERROR;
	  }
	lexptr = p;
	return toktype;
      }

    case '+':
      HANDLE_TOKEN2 ("+=", ASSIGN_MODIFY, BINOP_ADD);
      HANDLE_TOKEN2 ("++", INCREMENT, BINOP_END);
      lexptr++;
      return c;
    case '*':
      HANDLE_TOKEN2 ("*=", ASSIGN_MODIFY, BINOP_MUL);
      lexptr++;
      return c;
    case '/':
      HANDLE_TOKEN2 ("/=", ASSIGN_MODIFY, BINOP_DIV);
      lexptr++;
      return c;
    case '%':
      HANDLE_TOKEN2 ("%=", ASSIGN_MODIFY, BINOP_REM);
      lexptr++;
      return c;
    case '|':
      HANDLE_TOKEN2 ("|=", ASSIGN_MODIFY, BINOP_BITWISE_IOR);
      HANDLE_TOKEN2 ("||", OROR, BINOP_END);
      lexptr++;
      return c;
    case '&':
      HANDLE_TOKEN2 ("&=", ASSIGN_MODIFY, BINOP_BITWISE_AND);
      HANDLE_TOKEN2 ("&&", ANDAND, BINOP_END);
      lexptr++;
      return c;
    case '^':
      HANDLE_TOKEN2 ("^=", ASSIGN_MODIFY, BINOP_BITWISE_XOR);
      lexptr++;
      return c;
    case '!':
      HANDLE_TOKEN2 ("!=", NOTEQUAL, BINOP_END);
      lexptr++;
      return c;
    case '<':
      HANDLE_TOKEN3 ("<<=", ASSIGN_MODIFY, BINOP_LSH);
      HANDLE_TOKEN2 ("<=", LEQ, BINOP_END);
      HANDLE_TOKEN2 ("<<", LSH, BINOP_END);
      lexptr++;
      return c;
    case '>':
      HANDLE_TOKEN3 (">>=", ASSIGN_MODIFY, BINOP_RSH);
      HANDLE_TOKEN2 (">=", GEQ, BINOP_END);
      HANDLE_TOKEN2 (">>", RSH, BINOP_END);
      lexptr++;
      return c;
    case '=':
      HANDLE_TOKEN2 ("==", EQUAL, BINOP_END);
      lexptr++;
      return c;
    case ':':
      HANDLE_TOKEN2 ("::", COLONCOLON, BINOP_END);
      lexptr++;
      return c;

    case '[':
    case ']':
    case '?':
    case '@':
    case '~':
    case '{':
    case '}':
    symbol:
      lexptr++;
      return c;

    case '"':

      /* Build the gdb internal form of the input string in tempbuf,
	 translating any standard C escape forms seen.  Note that the
	 buffer is null byte terminated *only* for the convenience of
	 debugging gdb itself and printing the buffer contents when
	 the buffer contains no embedded nulls.  Gdb does not depend
	 upon the buffer being null byte terminated, it uses the length
	 string instead.  This allows gdb to handle C strings (as well
	 as strings in other languages) with embedded null bytes */

      tokptr = ++tokstart;
      tempbufindex = 0;

      do {
        const char *char_start_pos = tokptr;

	/* Grow the static temp buffer if necessary, including allocating
	   the first one on demand. */
	if (tempbufindex + 1 >= tempbufsize)
	  {
	    tempbuf = (char *) realloc (tempbuf, tempbufsize += 64);
	  }
	switch (*tokptr)
	  {
	  case '\0':
	  case '"':
	    /* Do nothing, loop will terminate. */
	    break;
	  case '\\':
	    tokptr++;
	    c = parse_escape (&tokptr);
	    if (c == -1)
	      {
		continue;
	      }
	    tempbuf[tempbufindex++] = c;
	    break;
	  default:
	    c = *tokptr++;
            if (! host_char_to_target (c, &c))
              {
                int len = tokptr - char_start_pos;
                char *copy = alloca (len + 1);
                memcpy (copy, char_start_pos, len);
                copy[len] = '\0';

                error ("There is no character corresponding to `%s' "
                       "in the target character set `%s'.",
                       copy, target_charset ());
              }
            tempbuf[tempbufindex++] = c;
	    break;
	  }
      } while ((*tokptr != '"') && (*tokptr != '\0'));
      if (*tokptr++ != '"')
	{
	  error ("Unterminated string in expression.");
	}
      tempbuf[tempbufindex] = '\0';	/* See note above */
#if 1
      free (tempbuf);
      error ("Unexpected string literal.");
#else
      yylval.sval.ptr = tempbuf;
      yylval.sval.length = tempbufindex;
      lexptr = tokptr;
      return (STRING);
#endif
    }

  if (!(c == '_' || c == '$' || ISALPHA (c)))
    /* We must have come across a bad character (e.g. ';').  */
    error ("Invalid character '%c' in expression.", c);

  /* It's a name.  See how long it is.  */
  namelen = 0;
  for (c = tokstart[namelen];
       ISALNUM (c) || c == '_' || c == '$'; )
    c = tokstart[++namelen];

  lexptr += namelen;

  /* Catch specific keywords.  Notice that some of the keywords contain
     spaces, and are sorted by the length of the first word.  They must
     all include a trailing space in the string comparison.  */
  switch (namelen)
    {
    case 16:
      if (strncmp (tokstart, "reinterpret_cast", 16) == 0)
        return REINTERPRET_CAST;
      break;
    case 12:
      if (strncmp (tokstart, "construction vtable for ", 24) == 0)
	{
	  lexptr = tokstart + 24;
	  return CONSTRUCTION_VTABLE;
	}
      if (strncmp (tokstart, "dynamic_cast", 12) == 0)
        return DYNAMIC_CAST;
      break;
    case 11:
      if (strncmp (tokstart, "static_cast", 11) == 0)
        return STATIC_CAST;
      break;
    case 9:
      HANDLE_SPECIAL ("covariant return thunk to ", D_COMP_COVARIANT_THUNK);
      HANDLE_SPECIAL ("reference temporary for ", D_COMP_REFTEMP);
      break;
    case 8:
      HANDLE_SPECIAL ("typeinfo for ", D_COMP_TYPEINFO);
      HANDLE_SPECIAL ("typeinfo fn for ", D_COMP_TYPEINFO_FN);
      HANDLE_SPECIAL ("typeinfo name for ", D_COMP_TYPEINFO_NAME);
      if (strncmp (tokstart, "operator", 8) == 0)
	return OPERATOR;
      if (strncmp (tokstart, "restrict", 8) == 0)
	return RESTRICT;
      if (strncmp (tokstart, "unsigned", 8) == 0)
	return UNSIGNED;
      if (strncmp (tokstart, "template", 8) == 0)
	return TEMPLATE;
      if (strncmp (tokstart, "volatile", 8) == 0)
	return VOLATILE_KEYWORD;
      break;
    case 7:
      HANDLE_SPECIAL ("virtual thunk to ", D_COMP_VIRTUAL_THUNK);
      if (strncmp (tokstart, "wchar_t", 7) == 0)
	return WCHAR_T;
      break;
    case 6:
      if (strncmp (tokstart, "global constructors keyed to ", 29) == 0)
	{
	  const char *p;
	  lexptr = tokstart + 29;
	  yylval.typed_val_int.val = GLOBAL_CONSTRUCTORS;
	  /* Find the end of the symbol.  */
	  p = symbol_end (lexptr);
	  yylval.typed_val_int.type = cp_v3_d_make_name (di, lexptr, p - lexptr);
	  lexptr = p;
	  return GLOBAL;
	}
      if (strncmp (tokstart, "global destructors keyed to ", 28) == 0)
	{
	  const char *p;
	  lexptr = tokstart + 28;
	  yylval.typed_val_int.val = GLOBAL_DESTRUCTORS;
	  /* Find the end of the symbol.  */
	  p = symbol_end (lexptr);
	  yylval.typed_val_int.type = cp_v3_d_make_name (di, lexptr, p - lexptr);
	  lexptr = p;
	  return GLOBAL;
	}

      HANDLE_SPECIAL ("vtable for ", D_COMP_VTABLE);
      if (strncmp (tokstart, "delete", 6) == 0)
	return DELETE;
      if (strncmp (tokstart, "struct", 6) == 0)
	return STRUCT;
      if (strncmp (tokstart, "signed", 6) == 0)
	return SIGNED_KEYWORD;
      if (strncmp (tokstart, "sizeof", 6) == 0)
	return SIZEOF;
      if (strncmp (tokstart, "double", 6) == 0)
	return DOUBLE_KEYWORD;
      break;
    case 5:
      HANDLE_SPECIAL ("guard variable for ", D_COMP_GUARD);
      if (strncmp (tokstart, "false", 5) == 0)
	return FALSEKEYWORD;
      if (strncmp (tokstart, "class", 5) == 0)
	return CLASS;
      if (strncmp (tokstart, "union", 5) == 0)
	return UNION;
      if (strncmp (tokstart, "float", 5) == 0)
	return FLOAT_KEYWORD;
      if (strncmp (tokstart, "short", 5) == 0)
	return SHORT;
      if (strncmp (tokstart, "const", 5) == 0)
	return CONST_KEYWORD;
      break;
    case 4:
      if (strncmp (tokstart, "void", 4) == 0)
	return VOID;
      if (strncmp (tokstart, "bool", 4) == 0)
	return BOOL;
      if (strncmp (tokstart, "char", 4) == 0)
	return CHAR;
      if (strncmp (tokstart, "enum", 4) == 0)
	return ENUM;
      if (strncmp (tokstart, "long", 4) == 0)
	return LONG;
      if (strncmp (tokstart, "true", 4) == 0)
	return TRUEKEYWORD;
      break;
    case 3:
      HANDLE_SPECIAL ("VTT for ", D_COMP_VTT);
      HANDLE_SPECIAL ("non-virtual thunk to ", D_COMP_THUNK);
      if (strncmp (tokstart, "new", 3) == 0)
	return NEW;
      if (strncmp (tokstart, "int", 3) == 0)
	return INT_KEYWORD;
      break;
    default:
      break;
    }

  yylval.comp = cp_v3_d_make_name (di, tokstart, namelen);
  return NAME;
}

void
yyerror (msg)
     char *msg;
{
  if (prev_lexptr)
    lexptr = prev_lexptr;

  error ("A %s in expression, near `%s'.\n", (msg ? msg : "error"), lexptr);
}

static const char *
symbol_end (const char *lexptr)
{
  const char *p = lexptr;

  while (*p && (ISALNUM (*p) || *p == '_' || *p == '$' || *p == '.'))
    p++;

  return p;
}

static char *
cp_comp_to_string (struct d_comp *result, int estimated_len)
{
  char *str, *prefix = NULL, *buf;
  int err = 0;

  if (result->type == GLOBAL_DESTRUCTORS)
    {
      result = d_left (result);
      prefix = "global destructors keyed to ";
    }
  else if (result->type == GLOBAL_CONSTRUCTORS)
    {
      result = d_left (result);
      prefix = "global constructors keyed to ";
    }

  str = cp_v3_d_print (DMGL_PARAMS | DMGL_ANSI, result, estimated_len, &err);
  if (str == NULL)
    return NULL;

  if (prefix == NULL)
    return str;

  buf = malloc (strlen (str) + strlen (prefix) + 1);
  strcpy (buf, prefix);
  strcat (buf, str);
  free (str);
  return (buf);
}

/* Return the canonicalized form of STRING, or NULL if STRING can not be
   parsed.  */

char *
cp_canonicalize_string (const char *string)
{
  int len = strlen (string);
  char *ret;

  len = len + len / 8;

  lexptr = string;
  di = cp_v3_d_init_info_alloc (NULL, DMGL_PARAMS | DMGL_ANSI, len);
  if (yyparse () || result == NULL)
    return NULL;

  ret = cp_comp_to_string (result, len);

  cp_v3_d_free_info (di);

  return ret;
}

#ifdef TEST_CPNAMES

static void
cp_print (struct d_comp *result, int len)
{
  char *str;
  int err = 0;

  if (result->type == GLOBAL_DESTRUCTORS)
    {
      result = d_left (result);
      puts ("global destructors keyed to ");
    }
  else if (result->type == GLOBAL_CONSTRUCTORS)
    {
      result = d_left (result);
      puts ("global constructors keyed to ");
    }

  str = cp_v3_d_print (DMGL_PARAMS | DMGL_ANSI, result, len, &err);
  if (str == NULL)
    return;

  puts (str);

  free (str);
}

static char
trim_chars (char *lexptr, char **extra_chars)
{
  char *p = (char *) symbol_end (lexptr);
  char c = 0;

  if (*p)
    {
      c = *p;
      *p = 0;
      *extra_chars = p + 1;
    }

  return c;
}

int
main (int argc, char **argv)
{
  char *str2, *extra_chars, c;
  char buf[65536];
  int arg;

  arg = 1;
  if (argv[arg] && strcmp (argv[arg], "--debug") == 0)
    {
      yydebug = 1;
      arg++;
    }

  if (argv[arg] == NULL)
    while (fgets (buf, 65536, stdin) != NULL)
      {
	int len;
	result = NULL;
	buf[strlen (buf) - 1] = 0;
	/* Use DMGL_VERBOSE to get expanded standard substitutions.  */
	c = trim_chars (buf, &extra_chars);
	str2 = cplus_demangle (buf, DMGL_PARAMS | DMGL_ANSI | DMGL_VERBOSE);
	lexptr = str2;
	if (lexptr == NULL)
	  {
	    /* printf ("Demangling error\n"); */
	    if (c)
	      printf ("%s%c%s\n", buf, c, extra_chars);
	    else
	      printf ("%s\n", buf);
	    continue;
	  }
	len = strlen (lexptr);
	di = cp_v3_d_init_info_alloc (NULL, DMGL_PARAMS | DMGL_ANSI, len);
	if (yyparse () || result == NULL)
	  continue;
	cp_print (result, len);
	free (str2);
	if (c)
	  {
	    putchar (c);
	    puts (extra_chars);
	  }
	putchar ('\n');
	cp_v3_d_free_info (di);
      }
  else
    {
      int len;
      lexptr = argv[arg];
      len = strlen (lexptr);
      di = cp_v3_d_init_info_alloc (NULL, DMGL_PARAMS | DMGL_ANSI, len);
      if (yyparse () || result == NULL)
	return 0;
      cp_print (result, len);
      cp_v3_d_free_info (di);
    }
  return 0;
}

#endif
