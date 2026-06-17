#-

#: MaxTermSize 300K
#: SmallSize 2G

On fewerstats,0;
Off threadstats;
On humanstats;
On sortverbose;

Symbol x,ep,q12;
Symbol n1,...,n12,m1,...,m12;
CFunction nptri3lm,nptri3l;
CFunction prf,num,den,numep,denep;
CFunction sectorid,level;
PolyRatFun prf;

#include inc/reduce-nptri3l.h

#ifndef `DIFFICULTY'
	#define DIFFICULTY "1"
#endif

#define n1 "2"
#define n2 "1"
#define n3 "1"
#define n4 "1"
#define n5 "1"
#define n6 "1"
#define n7 "1"
#define n8 "1"
#define n9 "1"
#if `DIFFICULTY' == 1
	#define n10 "-1"
	#define n11 "-1"
	#define n12 "-1"
#elseif `DIFFICULTY' == 2
	#define n10 "-2"
	#define n11 "-2"
	#define n12 "-1"
#else
	#define n10 "-2"
	#define n11 "-2"
	#define n12 "-2"
#endif

Local test = nptri3l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9',`n10',`n11',`n12');
.sort

#call reducenptri3l(PRFALLMERGE,BYLEVEL)
.sort

Drop;
Local check = test - (
	#include- inc/nptri3l-res`n1'`n2'`n3'`n4'`n5'`n6'`n7'`n8'`n9'`n10'`n11'`n12'.h
);
Print;
.sort

#if `ZERO_check' != 1
	#message Error in reduction of nptri3l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9',`n10',`n11',`n12')
	#terminate
#endif
.end
