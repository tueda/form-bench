#-

* Run a sort which fits in the small buffer. Don't create any large patches.
* TFORM default TermsInSmall is 3M
#: TermsInSmall 4200000
#: SmallSize 1500M

#ifndef `COMPR'
	#define COMPR ""
#endif
`COMPR'

#define BLOWUP "{2^6}"
#define NTERMS "{2^16}"
#define TERMPADDING "6"

On stats;
On fewerstats,0;
On threadstats;
On sortverbose;
On humanstats;

#include- ../sort-large/sort-test.h

.end
