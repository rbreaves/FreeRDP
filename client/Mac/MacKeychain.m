#import "MacKeychain.h"

#import <Security/Security.h>

static NSString *mac_keychain_service_name(NSString *serverName)
{
	if (!serverName || ([serverName length] == 0))
		return nil;

	return [NSString stringWithFormat:@"MacFreeRDP:%@", serverName];
}

static NSString *mac_keychain_account_name(NSString *username, NSString *domain)
{
	if (!username || ([username length] == 0))
		return nil;

	if (domain && ([domain length] > 0))
		return [NSString stringWithFormat:@"%@\\%@", domain, username];

	return username;
}

static NSMutableDictionary *mac_keychain_query(NSString *serverName, NSString *username,
	                                           NSString *domain)
{
	NSString *serviceName = mac_keychain_service_name(serverName);
	NSString *accountName = mac_keychain_account_name(username, domain);

	if (!serviceName || !accountName)
		return nil;

	NSMutableDictionary *query = [NSMutableDictionary dictionary];
	[query setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
	[query setObject:serviceName forKey:(id)kSecAttrService];
	[query setObject:accountName forKey:(id)kSecAttrAccount];
	[query setObject:@"MacFreeRDP" forKey:(id)kSecAttrLabel];
	return query;
}

NSString *mac_keychain_copy_password(NSString *serverName, NSString *username, NSString *domain)
{
	NSMutableDictionary *query = mac_keychain_query(serverName, username, domain);
	CFTypeRef result = NULL;
	OSStatus status = errSecParam;

	if (!query)
		return nil;

	[query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
	[query setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];

	status = SecItemCopyMatching((CFDictionaryRef)query, &result);
	if (status != errSecSuccess)
		return nil;

	NSData *passwordData = (NSData *)result;
	NSString *password = [[[NSString alloc] initWithData:passwordData
	                                             encoding:NSUTF8StringEncoding] autorelease];
	if (result)
		CFRelease(result);

	return password;
}

BOOL mac_keychain_store_password(NSString *serverName, NSString *username, NSString *domain,
                                 NSString *password)
{
	NSMutableDictionary *query = mac_keychain_query(serverName, username, domain);
	NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
	OSStatus status = errSecParam;

	if (!query || !passwordData || ([passwordData length] == 0))
		return NO;

	NSDictionary *update = [NSDictionary dictionaryWithObject:passwordData
	                                                   forKey:(id)kSecValueData];
	status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
	if (status == errSecItemNotFound)
	{
		[query setObject:passwordData forKey:(id)kSecValueData];
		status = SecItemAdd((CFDictionaryRef)query, NULL);
	}

	return (status == errSecSuccess);
}

BOOL mac_keychain_delete_password(NSString *serverName, NSString *username, NSString *domain)
{
	NSMutableDictionary *query = mac_keychain_query(serverName, username, domain);
	OSStatus status = errSecParam;

	if (!query)
		return NO;

	status = SecItemDelete((CFDictionaryRef)query);
	return (status == errSecSuccess) || (status == errSecItemNotFound);
}