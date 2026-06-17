#-

#: MaxTermSize 7M
#: WorkSpace 200M

Symbol x,ep,s12,s23,s34,s45,s15;
Symbol n1,...,n5,m1,...,m5;
CFunction pent1lm,pent1l;
CFunction prf,num,den,numep,denep;
CFunction sectorid,level;
PolyRatFun prf;

#include inc/reduce-pent1l.h

#ifndef `DIFFICULTY'
	#define DIFFICULTY "1"
#endif

*  7M MTS good for 3,3,3,3,2
* 11M MTS good for 3,3,3,3,3

#define n1 "3"
#define n2 "3"
#define n3 "3"
#if `DIFFICULTY' == 1
	#define n4 "2"
	#define n5 "2"
#else
	#define n4 "3"
	#define n5 "2"
#endif

Local test = pent1l(`n1',`n2',`n3',`n4',`n5');
.sort

#call reducepent1l(PRFALLMERGE,ANYLEVEL)
.sort

Drop;
Local check = test - (
	#include- inc/pent1l-res`n1'`n2'`n3'`n4'`n5'.h
);
Print;
.sort

#if `ZERO_check' != 1
	#message Error in reduction of pent1l(`n1',`n2',`n3',`n4',`n5')
	#terminate
#endif
.end
