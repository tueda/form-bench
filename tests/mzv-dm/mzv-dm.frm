#-

* This is a minor modification of "hexall.frm" from the MZV datamine,
* https://www.nikhef.nl/~form/datamine/alternating/rational/alldepth/alldepth.html
* Here we just use the modern default buffer sizes (and we are not pushing
* the program to the limit for benchmarking).

#ifndef `DIFFICULTY'
	#define DIFFICULTY "1"
#endif
#if `DIFFICULTY' == 1
	#define WEIGHT "9"
#else
	#define WEIGHT "10"
#endif

#if `WEIGHT' > 10
	#message Missing alt tables for WEIGHT `WEIGHT'
	#terminate
#endif

* The original code follows, with a modification to check a correct result at the end.


*	Program to compute the complete alternating MZV's
*	of a given weight (indicated by the parameter WEIGHT).
*
*	Settings via form.set because they are rather detailed.
*	And we carry this program between computers of different types.
*	Don't forget to disable the Modulus in form.set!!!!!!
*
*	We need the alt tables in separate files.
*	We assume that these tables only contain finite elements.
*
*	Program is an adaptation of hex.frm.
*	Made by J.Vermaseren, 8-aug-2008
*
*--#[ Settings :
*
*#define ONLYBASIS "1"
*
#ifndef `WEIGHT'
#define WEIGHT "9"
#endif
#define MAXDEPTH "16"
#if ( `MAXDEPTH' > `WEIGHT' )
#redefine MAXDEPTH "`WEIGHT'"
#endif
*
*   Below is the optimum as determined in a number of trial runs.
*   It isn't 100% clear though whether this optimum has survived
*   later changes in orderings.
*
*#define GROUPING "1024"
#ifndef `GROUPING'
#switch `WEIGHT'
#case 12
	#define GROUPING "2048"
#break
#default
#$ngrouping = {2^{((4*3^{`WEIGHT'-2})^%)/2+2}};
#define GROUPING "`$ngrouping'"
#break
#endswitch
#endif
#ifdef `ONLYBASIS'
*#define MODULUS "2147479273"
#endif
#include hexall.h
#ifdef `MODULUS'
#message Run with Weight = `WEIGHT', GROUPING = `GROUPING', Calculus modulus `MODULUS'
#else
#message Run with Weight = `WEIGHT', GROUPING = `GROUPING', Rational calculus
#endif
#ifndef `ONLYBASIS'
#call readalts({`WEIGHT'-1})
#endif
.global
*--#] Settings : 
*--#[ Master Equation :
*
*   Construct the expression FF that will contain the final result.
*	We only do the finite elements.
*   At first it will contain 2^{`WEIGHT'-2} objects but duality will
*	remove either half or almost half the elements.
*
S	xmaxpow(:`MAXDEPTH');
Off Parallel;
L   FF = E(`WEIGHT'-2,1)*xmaxpow+E(`WEIGHT'-2,-1)*xmaxpow;
repeat id E(n?pos_,?a) = E(n-1,0,?a)+E(n-1,1,?a)*xmaxpow+E(n-1,-1,?a)*xmaxpow;
id	E(0,?a) = E(0,?a)+E(-1,?a)*xmaxpow;
id	xmaxpow^n? = 1;
.sort
On Parallel;
id  E(?a)=E(?a)*H(?a);

#call frombasis(`WEIGHT')

*
*	The following enforces a better ordering inside the equations.
*
#call convert(E,`WEIGHT',0)
#call convert(H,`WEIGHT',0)
*
*   The bracket is essential!
*
B+   E;
.sort
Off Statistics;
Hide FF;
.sort
*
*   $count will tell what is the number of the identity we are constructing
*   $dcount tell how many H-function have not been eliminated yet.
*	$jj counts the elements in the group that we treat simultaneously.
*
#$count = 0;
#$dcount = termsin_(FF) - 1;
#$jj = 0;
*
*--#] Master Equation : 
*--#[ The relations :
*

#do DEPTH = 1,`MAXDEPTH'
#message entering DEPTH = `DEPTH'
*
*--#[ Stuffles :
*
#if ( `DEPTH' > 1 )
#message doing stuffles
*
Off Parallel;
L	Gen = E(`DEPTH')*EE({`WEIGHT'-`DEPTH'-1});
id	EE(-1) = 1;
repeat id E(x?{>1},?a) = E(x-1,1,?a);
repeat id EE(x?pos_,?a) = EE(x-1,0,?a);
id	EE(?a) = E(?a);
shuffle,E;
id	E(?a,0) = 0;
.sort
On Parallel;
ArgImplode,E;
id	E(?a) = E(?a)*fff(?a);
Multiply replace_(fff,ffs);
#do i = 1,`DEPTH'
id	ffs(x?,?a) = ffs(?a)*fun`i'(-x);
#enddo
id	ffs(?a) = 1;
id E(x?,?b) = EE(x)*E(?b)+EE(-x)*E(?b);
repeat id EE(?a)*E(x?,?b) = EE(?a,x)*E(?b)+EE(?a,-x)*E(?b);
id	EE(?a)*E = E(?a);
*----------------------------------------------------------------
*id	E(x1?,...,x`DEPTH'?) =
*#do i = 1,`DEPTH'/2
*		+E(x1,...,x`i')*E(<x{`i'+1}>,...,<x`DEPTH'>)*funa0(`i')
*#enddo
*		;
*----------------------------------------------------------------
Multiply,(
#do i = 1,`DEPTH'/2
	+EE(`i')*funa0(`i')
#enddo
		);
repeat id EE(x?pos_,?a)*E(x1?,?b) = EE(x-1,?a,x1)*E(?b);
id	EE(0,?a) = E(?a);
*----------------------------------------------------------------
id	E(1,?a) = 0;
.sort
DropCoefficient;
id	E(x1?,?a)*E(x2?,?b) = E(x1,?a)*E(x2,?b)*funa2(-min_(abs_(x1),abs_(x2)));
ArgExplode,E;
.sort
Off Parallel;
InParallel;
Drop Gen;
#do relation = Gen
	#$jj = $jj+1;
	L	F`$jj' = `relation';
	#if ( `$jj' >= `GROUPING' )
		#call solvestuffle
		#$jj = 0;
	#endif
#enddo
#call solvestuffle
#$jj = 0;
.sort
#endif
*
*--#] Stuffles : 
*--#[ Shuffles :
*
#if ( `DEPTH' > 1 )
*
#do SHUFFLE = 1,1
#message doing shuffles (`SHUFFLE')({`DEPTH'-`SHUFFLE'})
*
Off Parallel;
L	Gen = E(`DEPTH')*EE({`WEIGHT'-`DEPTH'-1});
id	EE(-1) = 1;
repeat id E(x?{>1},?a) = E(x-1,1,?a);
repeat id EE(x?pos_,?a) = EE(x-1,0,?a);
id	EE(?a) = E(?a);
shuffle,E;
id	E(?a,0) = 0;
ArgImplode,E;
Multiply EE;
#do i = 1,`SHUFFLE'
	id	EE(?a)*E(x?,?b) = EE(?a,x)*E(?b);
#enddo
id	EE(?a) = E(?a);
.sort
On Parallel;
DropCoefficient;
*
*	The next sets the lower weight in the single depth object first.
*
id	E(x1?) = E(x1)*fun(x1);
*id	E(x1?) = E(x1)*fun(abs_(x1));
*
*	Look for the number of ones. The fewer the better.
*
#do i = 1,1
id	E(?a) = E(R,R(?a));
repeat;
	id E(R(?a),R(`i',?b)) = E(R(?a,`i'),R(?b))*x;
	id E(R(?a),R(x1?!{`i',`i'},?b)) = E(R(?a,x1),R(?b));
endrepeat;
id	E(R(?a),R) = E(?a);
id	x^n? = fun`i'(n);
#enddo
*
*   Empirical restrictions
*
*id  E(1,x?,?a) = 0;
*if ( count(fun0,1) == 2 );
*elseif ( match(fun0(1)) );
*elseif ( match(fun1(0)) );
*elseif ( match(fun1(1)*fun0(2)) );
*else;
*    Discard;
*endif;
*
*	Look for sum of squares of indices
*
id	E(x1?,?a) = E(x1^2,R(x1),R(?a));
repeat id E(x?,R(?a),R(x1?,?b)) = E(x+x1^2,R(?a,x1),R(?b));
id	E(x?,R(?a),R) = E(x,?a);
id	E(x1?,?a)*E(x2?,?b) = E(?a)*E(?b)*funa1(-max_(x1,x2));
*
*	Look for the leading index.
*
id	E(x1?,?a)*E(x2?,?b) = E(x1,?a)*E(x2,?b)*funa2(-min_(x1,x2))*funa3(-x1-x2);
*
*	Number of negative indices
*
repeat;
	id,once,E(?a) = EE(?a)*Eb;
	repeat id EE(x?,?a)*Eb(?b) = EE(?a)*Eb(?b,x)+EE(?a)*Eb(?b,-x)*xs;
	id	EE = 1;
	id	Eb(?a) = Ec(?a);
endrepeat;
id	Ec(?a) = E(?a);
id	E(1,1,?a) = 0;
id	E(1,x?,?a) = 0;
id	E(1)^2 = 0;
id	xs^n? = fun(-n);
*id	xs^n? = 1;
*
if ( match(E(x?)) );
	id	E(x?)*E(?a) = E(x)*E(?a)*EE(x,?a)*ffs;
else;
	id	E(?b)*E(?a) = E(?b)*E(?a)*EE(?b,?a)*ffs;
endif;
repeat id	ffs(?a)*EE(x?,?b) = ffs(?a,sig_(x))*EE(?b);
id	EE = 1;
id	ffs(?a) = funa0(?a);
ArgExplode,E;
.sort
DropCoefficient;
.sort
#$jj = 0;
InParallel;
Drop Gen;
#do relation = Gen
	#$jj = $jj+1;
	L	F`$jj' = `relation';
	#if ( `$jj' >= `GROUPING' )
		#call solveshuffle
		#$jj = 0;
	#endif
#enddo
#call solveshuffle
#$jj = 0;
.sort
#enddo
#endif
*
*--#] Shuffles : 
*--#[ Double :
*
#message doing doubling
Off Parallel;
L	Gen = E(`DEPTH')*EE(`WEIGHT'-`DEPTH'-1);
id	EE(-1) = 0;
repeat id E(x?{>1},?a) = E(x-1,1,?a);
repeat id EE(x?pos_,?a) = EE(x-1,0,?a);
id	EE(?a) = E(?a);
Shuffle,E;
id	E(1,?a) = 0;
id	E(?a,0) = 0;
.sort
DropCoefficient;
.sort
#$jj = 0;
InParallel;
Drop Gen;
#do relation = Gen
	#$jj = $jj+1;
	L	F`$jj' = `relation';
	#if ( `$jj' >= `GROUPING' )
		#call solvedouble
		#$jj = 0;
	#endif
#enddo
#call solvedouble
#$jj = 0;
.sort
*
*--#] Double : 
*--#[ GenDouble :
*
#if ( ( `DEPTH' > 1 ) && ( `DEPTH' <= {`WEIGHT'-4} ) )
#message doing generalized doubling
Off Parallel;
L	Gen = E(`DEPTH')*EE(`WEIGHT'-`DEPTH'-1);
id	EE(-1) = 0;
repeat id E(x?{>1},?a) = E(x-1,1,?a);
repeat id EE(x?pos_,?a) = EE(x-1,0,?a);
id	EE(?a) = E(?a);
Shuffle,E;
id	E(1,?a) = 0;
id	E(?a,0) = 0;
.sort
DropCoefficient;
ArgImplode,E;
id	E(?a,x?) = E(?a)*EE(x);
repeat id E(?a,x1?,x2?)*EE(?b) = E(?a,x1)*(EE(x2,?b)+EE(-x2,?b));
id	E(?a)*EE(?b) = E(?a,?b);
.sort
#$jj = 0;
InParallel;
Drop Gen;
#do relation = Gen
	#$jj = $jj+1;
	L	F`$jj' = `relation';
	#if ( `$jj' >= `GROUPING' )
		#call solvegendouble
		#$jj = 0;
	#endif
#enddo
#call solvegendouble
#$jj = 0;
.sort
#endif
*
*--#] GenDouble : 
*
#enddo
*
*--#] The relations : 
*--#[ Output :
.sort
Drop;
ndrop FF;
.sort
On Statistics;
On Parallel;
Format nospaces;
Format 80;
UnHide FF;
*
*   In the output the bracket indicates the H-function and the contents of
*   the bracket what it is equal to.
*   The remaining H functions are renamed as HH. This way they can be
*   found easily in an editor.
*
#call convert(E,`WEIGHT',1)
#call convert(H,`WEIGHT',1)
id  H(?a) = HH(?a);
id  E(?a) = H(?a);
B   H;
*Print +f;
*--#] Output : 
.sort
*Off Parallel;
*ArgImplode,H;
*if ( count(HH,1) == 0 ) Discard;
*B	HH;
*Print +s;
*.sort
*B	HH;
*Print[] +f;
*.end

*--#[ Verify result
Off parallel;
Local diff = FF - (
	#include- ref/hexall-ref-`WEIGHT'.h
);
.sort
#if `ZERO_diff' == 0
	#message Error in WEIGHT `WEIGHT' result
	#terminate
#endif
*--#]
.end
