#-

* Run a sort which fits in the small buffer. Don't create any large patches.
* TFORM default TermsInSmall is 3M
#: TermsInSmall 9M
#: SmallSize 6G
#: LargeSize 100M
#: ScratchSize 100M

#define BLOWUP "{2^6}"
#define NTERMS "{2^17}"
#define TERMPADDING "6"

On stats;
On fewerstats,0;
Off threadstats;

#include- ../sort-large/sort-test.h

.end
