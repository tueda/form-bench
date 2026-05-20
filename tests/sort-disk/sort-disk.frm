#-

* Run a sort which overflows the large buffer, creating disk patches.

#define BLOWUP "{2^8}"
#define NTERMS "{2^17}"
#define TERMPADDING "25"

On stats;
On fewerstats,0;
Off threadstats;

#include- ../sort-large/sort-test.h

.end
