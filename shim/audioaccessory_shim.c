/*
 * audioaccessory_shim.c: Native MachService XPC Responder Shim
 *
 * BACKGROUND:
 * When no Aqua GUI user is logged in, lookups for `com.apple.AudioAccessoryServices`
 * and `com.apple.BluetoothServices` fail, causing audiomxd to continuously retry.
 *
 * This daemon acts as a lightweight MachService listener that accepts incoming
 * XPC requests and responds with empty dictionary / zero-error packets, preventing
 * the failure cycle.
 */

#include <stdio.h>
#include <stdlib.h>
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>

static void handle_peer(xpc_connection_t peer) {
    xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        if (type == XPC_TYPE_DICTIONARY) {
            xpc_object_t reply = xpc_dictionary_create_reply(event);
            if (reply) {
                xpc_dictionary_set_int64(reply, "kError", 0);
                xpc_connection_send_message(peer, reply);
                xpc_release(reply);
            }
        }
    });
    xpc_connection_resume(peer);
}

static void setup_service(const char *name) {
    xpc_connection_t listener = xpc_connection_create_mach_service(name, NULL, XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (!listener) {
        fprintf(stderr, "[-] Failed to register MachService listener: %s\n", name);
        return;
    }
    xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) == XPC_TYPE_CONNECTION) {
            handle_peer(peer);
        }
    });
    xpc_connection_resume(listener);
    printf("[+] Listening on MachService: %s\n", name);
}

int main(int argc, char **argv) {
    printf("[*] Starting AudioAccessory MachService Shim...\n");
    setup_service("com.apple.AudioAccessoryServices");
    setup_service("com.apple.BluetoothServices");
    printf("[+] Shim active. Entering dispatch_main...\n");
    fflush(stdout);
    dispatch_main();
    return 0;
}
