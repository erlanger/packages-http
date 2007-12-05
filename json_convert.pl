/*  $Id$

    Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        wielemak@science.uva.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 1985-2007, University of Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(json_convert,
	  [ prolog_to_json/2,		% +Term, -JSON object
	    json_to_prolog/2,		% :JSON, -Term
	    (json_object)/1,		% +Definition
	    op(1150, fx, (json_object))
	  ]).
:- use_module(library(error)).

:- module_transparent
	prolog_to_json/2,
	json_to_prolog/2.

/** <module> Convert between JSON terms and Prolog application terms

The idea behind this module is to  provide a flexible high-level mapping
between Prolog terms as you would like   to see them in your application
and the standard representation of a JSON   object as a Prolog term. For
example,  an  X-Y  point  may  be  represented  in  JSON  as  =|{"x":25,
"y":50}|=. Represented in Prolog this   becomes object([x=25,y=50]), but
this is a pretty non-natural  representation   from  the Prolog point of
view.

This module allows for defining records (just like library(record)) that
provide   transparent   two-way   transformation     between   the   two
representations.

==
:- json_object
	point(x:integer, y:integer).
==

This declaration causes prolog_to_json/2 to translate the native Prolog
representation into a JSON Term:

==
?- prolog_to_json(point(25,50), X).

X = object([x=25, y=50])
==

A json_object/1 declaration can define multiple   objects separated by a
comma (,), similar to the dynamic/1 directive. Optionally, a declaration
can  be  qualified  using   a    module.   The   converstion  predicates
prolog_to_json/2 and json_to_prolog/2 first try  a conversion associated
with the calling  module.  If  not   successful,  they  try  conversions
associated with the module =user=.

JSON objects have no _type_. This can be solved by adding an extra field
to the JSON object, e.g. =|{"type":"point", "x":25, "y":50}|=. As Prolog
records are typed by their functor we need some notation to handle this
gracefully. This is achieved by adding +Fields to the declaration. I.e.

==
:- json_object
	point(x:integer, y:integer) + [type=point].
==

Using this declaration, the conversion becomes:

==
?- prolog_to_json(point(25,50), X).

X = object([x=25, y=50, type=point])
==


*/

:- multifile
	json_object_to_pairs/3,		% Term, Module, Pairs
	current_json_object/3.		% Term, Module, Fields

%%	json_object(+Declaration)
%
%	Declare a JSON object.  The declaration takes the same format as
%	using in record/1 from library(record).  E.g.
%	
%	==
%	?- json_object
%		point(x:int, y:int, z:int=0).
%	==

json_object(Declaration) :-
	throw(error(context_error(nodirective, json_object(Declaration)), _)).


%%	compile_json_objects(+Spec, -Clauses) is det.
%
%	Compiles a :- json_object directive into Clauses. Clauses are of
%	the form:
%	
%	==
%	json_object_to_pairs(Term, Module, Pairs) :-
%		<type-checks on Term>,
%		<make Pairs from Term>.
%	==

compile_json_objects(Spec, Clauses) :-
	phrase(compile_objects(Spec), Clauses).

compile_objects(A) -->
	{ var(A), !,
	  instantiation_error(A)
	}.
compile_objects((A,B)) --> !,
	compile_objects(A),
	compile_objects(B).
compile_objects(Term) -->
	compile_object(Term).

compile_object(ObjectDef) -->
	{ prolog_load_context(module, CM),
	  strip_module(CM:ObjectDef, M, Def),
	  extra_defs(Def, Term, ExtraFields),
	  Term =.. [Constructor|Args],
	  defaults(Args, _Defs, TypedArgs),
	  types(TypedArgs, Names, Types)
	},
	record_to_json_clause(Constructor, M, Types, Names, ExtraFields),
	current_clause(Constructor, M, Types, Names, ExtraFields).

extra_defs(Term+Extra, Term, Extra) :- !.
extra_defs(Term,       Term, []).


%%	record_to_json_clause(+Constructor, +Module, +Type, +Names)
%
%	Create a clause translating the record   definition into a pairs
%	representation.

record_to_json_clause(Constructor, Module, Types, Names, Extra) -->
	{ type_checks(Types, Vars, Body0),
	  clean_body(Body0, Body),
	  Term =.. [Constructor|Vars],
	  make_pairs(Names, Vars, Pairs, Extra),
	  Head =.. [json_object_to_pairs,Term,Module,object(Pairs)]
	},
	[ (json_convert:Head :- Body) ].

	      
type_checks([], [], true).
type_checks([any|T], [_|Vars], Body) :-
	type_checks(T, Vars, Body).
type_checks([Type|T], [V|Vars], (Goal, Body)) :-
	type_goal(Type, V, Goal),
	type_checks(T, Vars, Body).

%%	type_goal(+Type, +Var, -BodyTerm) is det.
%
%	Inline type checking calls.

type_goal(Type, Var, Body) :-
	clause(error:has_type(Type, Var), Body), !.
type_goal(Type, Var, is_of_type(Type, Var)).


clean_body((A0,true), A) :- !,
	clean_body(A0, A).
clean_body((true,A0), A) :- !,
	clean_body(A0, A).
clean_body((A0,B0), (A,B)) :-
	clean_body(A0, A),
	clean_body(B0, B).
clean_body(A, A).

make_pairs([], [], L, L).
make_pairs([N|TN], [V|TV], [N=V|T], Tail) :-
	make_pairs(TN, TV, T, Tail).

%%	current_clause(+Constructor, +Module, +Type, +Names)
%
%	Create the clause current_json_object/3.

current_clause(Constructor, Module, Types, Names, Extra) -->
	{ length(Types, Arity),
	  functor(Term, Constructor, Arity),
	  extra_fields(Extra, EF),
	  mk_fields(Names, Types, Fields0, EF),
	  sort(Fields0, Fields),
	  Head =.. [current_json_object, Term, Module, Fields]
	},
	[ json_convert:Head ].
	
extra_fields([], []).
extra_fields([Name=Value|T0], [Name=oneof([Value])|T]) :-
	extra_fields(T0, T).

mk_fields([], [], Fields, Fields).
mk_fields([Name|TN], [Type|TT], [Name:Type|T], Tail) :-
	mk_fields(TN, TT, T, Tail).


/* The code below is copied from library(record) */

%%	defaults(+ArgsSpecs, -Defaults, -Args)
%
%	Strip the default specification from the argument specification.

defaults([], [], []).
defaults([Arg=Default|T0], [Default|TD], [Arg|TA]) :- !,
	defaults(T0, TD, TA).
defaults([Arg|T0], [_|TD], [Arg|TA]) :-
	defaults(T0, TD, TA).
	

%%	types(+ArgsSpecs, -Defaults, -Args)
%
%	Strip the default specification from the argument specification.

types([], [], []).
types([Name:Type|T0], [Name|TN], [Type|TT]) :- !,
	must_be(atom, Name),
	types(T0, TN, TT).
types([Name|T0], [Name|TN], [any|TT]) :-
	must_be(atom, Name),
	types(T0, TN, TT).


		 /*******************************
		 *       PROLOG --> JSON	*
		 *******************************/

%%	prolog_to_json(:Term, -JSONObject) is semidet.
%
%	Translate a Prolog application Term  into   a  JSON object term.
%	This transformation is based on :- json_object/1 declarations.

prolog_to_json(Term, JSON) :-
	strip_module(Term, M, T),
	record_to_pairs(T, M, JSON).

record_to_pairs(T, _, _) :-
	var(T), !,
	instantiation_error(T).
record_to_pairs(T, M, JSON) :-
	object_module(M, Module),
	json_object_to_pairs(T, Module, JSON), !.

object_module(M, M).
object_module(_, user).


		 /*******************************
		 *       JSON --> PROLOG	*
		 *******************************/

%%	json_to_prolog(+JSON, -Term) is semidet.
%
%	Translate  a  JSON  term   into    an   application  term.  This
%	transformation is based on  :-   json_object/1  declarations. An
%	efficient transformation is non-trivial,  but   we  rely  on the
%	assumption that, although the order of   fields in JSON terms is
%	irrelevant and can therefore vary  a lot, practical applications
%	will normally generate the JSON objects in a consistent order.

:- dynamic
	json_to_prolog_rule/3,		% Module, Pairs, Term
	no_rule_for_pairs/2.		% Module, Pairs

json_to_prolog(object(Pairs), Term) :-
	strip_module(Term, M, T),
	pairs_to_term(Pairs, M, T).

pairs_to_term(Pairs, Module, Term) :-
	object_module(Module, M),
	json_to_prolog_rule(M, Pairs, Term), !.
pairs_to_term(Pairs, Module, _) :-
	object_module(Module, M),
	no_rule_for_pairs(M, Pairs), !, fail.
pairs_to_term(Pairs, Module, Term) :-
	pairs_args(Pairs, PairArgs, Vars),
	(   create_rule(PairArgs, Vars, Module, M, Term0, Body)
	->  asserta((json_to_prolog_rule(M, PairArgs, Term0) :- Body)),
	    Pairs = PairArgs,
	    Term = Term0,
	    Body
	;   asserta(no_rule_for_pairs(M, PairArgs)), % TBD: types?
	    fail
	).
	
pairs_args([], [], []).
pairs_args([Name=_Value|T0], [Name=Var|T], [Var|TV]) :-
	pairs_args(T0, T, TV).

%%	create_rule(+PairArgs, +Vars, -Term, -Body) is det.
%
%	Create a new rule for dealing with Pairs, a Name=Value list of a
%	particular order.  Here is an example rule:
%	
%	==
%	json_to_prolog_rule([x=X, y=Y], point(X,Y), true) :-
%		integer(X),
%		integer(Y).
%	==

create_rule(PairArgs, Vars, Module, M, Term, Body) :-
	object_module(Module, M),
	current_json_object(Term, M, Fields),
	sort(PairArgs, SPA),
	match_fields(SPA, Fields, Body0),
	clean_body(Body0, Body),
	Term =.. [_|Vars].

match_fields([], [], true).
match_fields([Name=_|TP], [Name:any|TF], Body) :- !,
	match_fields(TP, TF, Body).
match_fields([Name=Var|TP], [Name:Type|TF], (Goal,Body)) :- !,
	type_goal(Type, Var, Goal),
	match_fields(TP, TF, Body).



		 /*******************************
		 *	      EXPANSION		*
		 *******************************/

:- multifile
	user:term_expansion/2.
:- dynamic
	user:term_expansion/2.

user:term_expansion((:- json_object(Spec)), Clauses) :-
	compile_json_objects(Spec, Clauses).
