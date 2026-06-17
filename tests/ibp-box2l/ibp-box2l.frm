#-

#: MaxTermSize 1M
#: WorkSpace 100M

On fewerstats,0;
Off threadstats;

Symbol x,ep,q12,q13;
Symbol n1,...,n9,m1,...,m9;
CFunction box2lm,box2l;
CFunction prf,num,den,numep,denep;
CFunction sectorid,level;
PolyRatFun prf;

#include inc/reduce-box2l.h

#ifndef `DIFFICULTY'
	#define DIFFICULTY "1"
#endif

#define n1 "2"
#define n2 "2"
#define n3 "2"
#define n4 "2"
#define n5 "2"
#define n6 "2"
#define n7 "2"
#if `DIFFICULTY' == 1
	#define n8 "-3"
	#define n9 "-3"
#elseif `DIFFICULTY' == 2
	#define n8 "-4"
	#define n9 "-4"
#else
	#define n8 "-5"
	#define n9 "-5"
#endif

Local test = box2l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9');
.sort

#call reducebox2l(PRFALLMERGE,BYLEVEL)
.sort

Drop;
Local check = test - (
	#include- inc/box2l-res`n1'`n2'`n3'`n4'`n5'`n6'`n7'`n8'`n9'.h
);
Print;
.sort

#if `ZERO_check' != 1
	#message Error in reduction of box2l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9')
	#terminate
#endif
.end
