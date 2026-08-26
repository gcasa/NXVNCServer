#import "NXVNCFramebuffer.h"
#import "NXVNCRFBServer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    int port = 5900;
    NXVNCFramebuffer *fb;
    NXVNCRFBServer *server;
    if (argc > 1) port = atoi(argv[1]);
    if (port < 1 || port > 65535) {
        fprintf(stderr, "usage: %s [port]\n", argv[0]);
        return 2;
    }
#ifdef NEXTSTEP
    fb = [NXVNCScreenFramebuffer new];
#else
    fb = [[NXVNCTestFramebuffer alloc] initWidth:640 height:480];
#endif
    if (fb == nil) { fprintf(stderr, "NXVNC: cannot create framebuffer\n"); return 1; }
    server = [[NXVNCRFBServer alloc] initWithFramebuffer:fb port:port];
    if (![server run]) return 1;
    return 0;
}

