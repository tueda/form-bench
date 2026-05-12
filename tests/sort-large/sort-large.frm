#-

* Run a sort which overflows the small buffer, and creates large patches. Don't
* overflow onto the disk, increase the default LargePatches for this.
#: LargePatches 1024
#: LargeSize 4G

#define BLOWUP "{2^8}"
#define NTERMS "{2^17}"
#define TERMPADDING "10"

On stats;
On fewerstats,0;
Off threadstats;

#include- sort-test.h

.end
