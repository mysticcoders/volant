/* Transport probe for the MCP server design (docs/mcp-server-design.md). One binary, signed with
   different entitlements by tools/spike-mcp-transport.py, answers whether a sandboxed process may
   listen on a Unix socket or on loopback TCP, and who may connect. Each mode exchanges one line. */
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

/* Prints a failed call with errno and exits non-zero. */
static int fail(const char *what) {
    printf("FAIL %s: %s (errno %d)\n", what, strerror(errno), errno);
    fflush(stdout);
    return 1;
}

/* Prints the connected peer's signing team and identifier, from its audit token. This is the check
   the app would make before reading a byte from a Unix socket client. */
static void describe_peer(int client) {
    audit_token_t token;
    socklen_t length = sizeof token;
    if (getsockopt(client, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) != 0) { printf("PEER token unavailable (errno %d)\n", errno); return; }
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)&token, sizeof token);
    const void *keys[] = {kSecGuestAttributeAudit};
    const void *values[] = {data};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecCodeRef code = NULL;
    CFDictionaryRef info = NULL;
    char team[64] = "none", identifier[256] = "none";
    if (SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info) == errSecSuccess) {
        CFStringRef value = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier);
        if (value) CFStringGetCString(value, team, sizeof team, kCFStringEncodingUTF8);
        value = CFDictionaryGetValue(info, kSecCodeInfoIdentifier);
        if (value) CFStringGetCString(value, identifier, sizeof identifier, kCFStringEncodingUTF8);
    }
    printf("PEER team=%s identifier=%s ", team, identifier);
    if (info) CFRelease(info);
    if (code) CFRelease(code);
    CFRelease(attributes);
    CFRelease(data);
}

/* Accepts one client, reads its line and answers pong. A TCP server also prints its port. */
static int answer(int server, int port) {
    if (port) printf("LISTENING %d\n", port); else printf("LISTENING\n");
    fflush(stdout);
    int client = accept(server, NULL, NULL);
    if (client < 0) return fail("accept");
    if (!port) describe_peer(client);
    char line[64] = {0};
    if (read(client, line, sizeof line - 1) <= 0) return fail("read");
    write(client, "pong\n", 5);
    printf("SERVED %s", line);
    close(client);
    return 0;
}

/* Sends ping and prints the reply. */
static int ping(int sock) {
    write(sock, "ping\n", 5);
    char line[64] = {0};
    if (read(sock, line, sizeof line - 1) <= 0) return fail("read reply");
    printf("CONNECTED reply %s", line);
    return 0;
}

int main(int argc, char **argv) {
    alarm(15);
    if (argc < 3) { fprintf(stderr, "usage: probe serve-unix|connect-unix <path> | serve-tcp - | connect-tcp <port>\n"); return 64; }
    const char *mode = argv[1];
    if (!strcmp(mode, "serve-unix") || !strcmp(mode, "connect-unix")) {
        struct sockaddr_un addr = {.sun_family = AF_UNIX};
        if (strlen(argv[2]) >= sizeof addr.sun_path) { printf("FAIL path too long\n"); return 1; }
        strcpy(addr.sun_path, argv[2]);
        int sock = socket(AF_UNIX, SOCK_STREAM, 0);
        if (sock < 0) return fail("socket");
        if (!strcmp(mode, "serve-unix")) {
            unlink(argv[2]);
            if (bind(sock, (struct sockaddr *)&addr, sizeof addr) < 0) return fail("bind");
            if (listen(sock, 1) < 0) return fail("listen");
            int result = answer(sock, 0);
            unlink(argv[2]);
            return result;
        }
        if (connect(sock, (struct sockaddr *)&addr, sizeof addr) < 0) return fail("connect");
        return ping(sock);
    }
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return fail("socket");
    if (!strcmp(mode, "serve-tcp")) {
        if (bind(sock, (struct sockaddr *)&addr, sizeof addr) < 0) return fail("bind");
        if (listen(sock, 1) < 0) return fail("listen");
        socklen_t length = sizeof addr;
        getsockname(sock, (struct sockaddr *)&addr, &length);
        return answer(sock, ntohs(addr.sin_port));
    }
    addr.sin_port = htons((unsigned short)atoi(argv[2]));
    if (connect(sock, (struct sockaddr *)&addr, sizeof addr) < 0) return fail("connect");
    return ping(sock);
}
