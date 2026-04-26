#ifndef FREERDP_CLIENT_MAC_KEYCHAIN_H
#define FREERDP_CLIENT_MAC_KEYCHAIN_H

#import <Cocoa/Cocoa.h>

NSString *mac_keychain_copy_password(NSString *serverName, NSString *username, NSString *domain);
BOOL mac_keychain_store_password(NSString *serverName, NSString *username, NSString *domain,
                                 NSString *password);
BOOL mac_keychain_delete_password(NSString *serverName, NSString *username, NSString *domain);

#endif /* FREERDP_CLIENT_MAC_KEYCHAIN_H */