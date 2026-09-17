#include <sys/types.h>
extern uid_t testUID,testEUID;
extern gid_t testGID,testEGID;
extern int opens,closes,uidCalls,gidCalls,failOpen,failUID,failGID,lieUID,regain;
void resetStartupFixture(void);
