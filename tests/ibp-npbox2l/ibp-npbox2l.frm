#-

#: MaxTermSize 1M
#: WorkSpace 100M

On fewerstats,0;
Off threadstats;

Symbol x,ep,q12,q13;
Symbol n1,...,n9,m1,...,m9;
CFunction npbox2lm,npbox2l;
CFunction prf,num,den,numep,denep;
CFunction sectorid,level;
PolyRatFun prf;

#include inc/reduce-npbox2l.h

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
	#define n8 "-1"
	#define n9 "-1"
#elseif `DIFFICULTY' == 2
	#define n8 "-2"
	#define n9 "-2"
#else
	#define n8 "-3"
	#define n9 "-3"
#endif

Local test = npbox2l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9');
.sort

#call reducenpbox2l(PRFALLMERGE,BYLEVEL)
.sort

Drop;
Local check = test - (
	#include- inc/npbox2l-res`n1'`n2'`n3'`n4'`n5'`n6'`n7'`n8'`n9'.h
);
Print;
.sort

#if `ZERO_check' != 1
	#message Error in reduction of npbox2l(`n1',`n2',`n3',`n4',`n5',`n6',`n7',`n8',`n9')
	#terminate
#endif
.end
