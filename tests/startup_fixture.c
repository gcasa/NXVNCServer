#include "NXVNCInput.h"
#include "startup_fixture.h"
#include <assert.h>
uid_t testUID,testEUID;
gid_t testGID,testEGID;
int opens,closes,uidCalls,gidCalls,failOpen,failUID,failGID,lieUID,regain;
void resetStartupFixture(void) {
  testUID=501; testEUID=0; testGID=testEGID=20;
  opens=closes=uidCalls=gidCalls=failOpen=failUID=failGID=lieUID=regain=0;
}
uid_t NXVNCTestGetUID(void) { return testUID; }
uid_t NXVNCTestGetEUID(void) { return testEUID; }
gid_t NXVNCTestGetGID(void) { return testGID; }
gid_t NXVNCTestGetEGID(void) { return testEGID; }
int NXVNCTestSetGID(gid_t gid) {
  assert(!uidCalls && gid==testGID); gidCalls++;
  if(failGID) return -1;
  testEGID=gid; return 0;
}
int NXVNCTestSetUID(uid_t uid) {
  assert(gidCalls==1); uidCalls++;
  if(uid==0) { if(!regain) return -1; testEUID=0; return 0; }
  assert(uid==testUID);
  if(failUID) return -1;
  if(!lieUID) testEUID=uid;
  return 0;
}
static int post(void *ctx,const NXVNCInputEvent *e) {
  (void)ctx; (void)e; assert(testEUID==testUID); return 1;
}
int NXVNCInputOpen(NXVNCInput *s,int w,int h) {
  assert(!uidCalls && !gidCalls && w==32768 && h==32768);
  opens++; if(failOpen) return 0;
  s->post=post; s->context=s; return 1;
}
void NXVNCInputClose(NXVNCInput *s) {
  closes++; s->post=0; s->context=0;
}
