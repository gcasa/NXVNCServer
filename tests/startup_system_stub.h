/* Credential calls are mocked; tests never change host privileges. */
uid_t NXVNCTestGetUID(void);
uid_t NXVNCTestGetEUID(void);
gid_t NXVNCTestGetGID(void);
gid_t NXVNCTestGetEGID(void);
int NXVNCTestSetUID(uid_t);
int NXVNCTestSetGID(gid_t);
#define getuid NXVNCTestGetUID
#define geteuid NXVNCTestGetEUID
#define getgid NXVNCTestGetGID
#define getegid NXVNCTestGetEGID
#define setuid NXVNCTestSetUID
#define setgid NXVNCTestSetGID
