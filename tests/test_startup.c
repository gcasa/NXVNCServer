#include "NXVNCStartup.h"
#include "startup_fixture.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
  NXVNCInput input;
  resetStartupFixture();
  assert(NXVNCPrepareInput(&input,1));
  assert(opens==1 && input.post && testUID==501 && testEUID==501);
  assert(gidCalls==1 && uidCalls==2);
  assert(NXVNCInputPointer(&input,3,4,0));
  resetStartupFixture();
  assert(NXVNCPrepareInput(&input,0));
  assert(!opens && !input.post && testEUID==501 && uidCalls==2);
  resetStartupFixture();failOpen=1;
  assert(NXVNCPrepareInput(&input,1));
  assert(opens==1 && !input.post && testEUID==501 && uidCalls==2);
  resetStartupFixture();failUID=1;
  assert(!NXVNCPrepareInput(&input,1) && closes==1 && !input.post);
  resetStartupFixture();failGID=1;
  assert(!NXVNCPrepareInput(&input,1) && closes==1 && !uidCalls);
  resetStartupFixture();lieUID=1;
  assert(!NXVNCPrepareInput(&input,1) && closes==1);
  resetStartupFixture();regain=1;
  assert(!NXVNCPrepareInput(&input,1) && closes==1);
  resetStartupFixture();testUID=0;
  assert(!NXVNCPrepareInput(&input,1) && !opens && !uidCalls);
  resetStartupFixture();testEUID=testUID;
  assert(NXVNCPrepareInput(&input,1) && !uidCalls && !gidCalls);
#ifdef NXVNC_INPUT_INTEL
  assert(!opens && !input.post);
#else
  assert(opens==1 && input.post);
#endif
  resetStartupFixture();testEGID=0;
  assert(NXVNCPrepareInput(&input,1) && testEGID==testGID && testEUID==testUID);
  puts("PASS: input acquisition precedes irreversible credential drop; failures abort, view-only drops, real root rejected");
  return 0;
}
