#-

#: MaxTermSize 6M
#: WorkSpace 200M

On fewerstats,0;
Off threadstats;

Symbol x,ep,q12,q13,q33,m2;
Symbol n1,...,n4,m1,...,m4;
CFunction mbox1lm,mbox1l;
CFunction prf,num,den,numep,denep;
CFunction sectorid,level;
PolyRatFun prf;

#include inc/reduce-mbox1l.h

#ifndef `DIFFICULTY'
	#define DIFFICULTY "3"
#endif

#if `DIFFICULTY' == 1
	#define n1 "3"
	#define n2 "3"
	#define n3 "3"
	#define n4 "3"
#elseif `DIFFICULTY' == 2
	#define n1 "4"
	#define n2 "3"
	#define n3 "3"
	#define n4 "3"
#else
	#define n1 "4"
	#define n2 "4"
	#define n3 "3"
	#define n4 "3"
#endif

Local test = mbox1l(`n1',`n2',`n3',`n4');
.sort

#call reducembox1l(PRFHOLDEP,ANYLEVEL)
.sort

CFunction mbox1lm1m;
Symbol M1;
Drop;
Local check = test - (
	#include- inc/mbox1l-res`n1'`n2'`n3'`n4'.h
);

Argument;
	Identify M1^2 = m2;
EndArgument;
Print;
.sort

#if `ZERO_check' != 1
	#message Error in reduction of mbox1l(`n1',`n2',`n3',`n4')
	#terminate
#endif
.end
