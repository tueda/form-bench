#-

#: MaxTermSize 100K
#: ScratchSize 1G

On fewerstats,0;
Off threadstats;

Symbol x,ep,q12;
Symbol n1,...,n12,m1,...,m12;
CFunction tri3lm,tri3l;
CFunction prf,num,den,numep,denep;
CFunction sectorid,level;
PolyRatFun prf;

#include inc/reduce-tri3l.h

#ifndef `DIFFICULTY'
	#define DIFFICULTY "1"
#endif

#define n1 "2"
#define n2 "2"
#define n3 "2"
#define n4 "2"
#define n5 "2"
#define n6 "2"
#if `DIFFICULTY' == 1
	#define n7 "1"
	#define n8 "1"
	#define n9 "1"
#elseif `DIFFICULTY' == 2
	#define n7 "2"
	#define n8 "2"
	#define n9 "1"
#else
	#define n7 "2"
	#define n8 "2"
	#define n9 "2"
#endif
#define n10 "-1"
#define n11 "-1"
#define n12 "-1"

Local test = tri3l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9',`n10',`n11',`n12');
.sort

#call reducetri3l(PRFALLMERGE,BYLEVEL)
.sort

Drop;
Local check = test - (
	#include- inc/tri3l-res`n1'`n2'`n3'`n4'`n5'`n6'`n7'`n8'`n9'`n10'`n11'`n12'.h
);
Print;
.sort

#if `ZERO_check' != 1
	#message Error in reduction of tri3l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9',`n10',`n11',`n12')
	#terminate
#endif
.end
