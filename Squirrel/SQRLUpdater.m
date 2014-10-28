//
//  SQRLUpdater.m
//  Squirrel
//
//  Created by Justin Spahr-Summers on 2013-07-21.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import "SQRLUpdater.h"
#import "NSBundle+SQRLVersionExtensions.h"
#import "NSError+SQRLVerbosityExtensions.h"
#import "NSProcessInfo+SQRLVersionExtensions.h"
#import "SQRLUpdate.h"
#import <ReactiveCocoa/EXTScope.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

NSString * const SQRLUpdaterErrorDomain = @"SQRLUpdaterErrorDomain";
NSString * const SQRLUpdaterServerDataErrorKey = @"SQRLUpdaterServerDataErrorKey";
NSString * const SQRLUpdaterJSONObjectErrorKey = @"SQRLUpdaterJSONObjectErrorKey";

const NSInteger SQRLUpdaterErrorMissingUpdateBundle = 2;
const NSInteger SQRLUpdaterErrorPreparingUpdateJob = 3;
const NSInteger SQRLUpdaterErrorRetrievingCodeSigningRequirement = 4;
const NSInteger SQRLUpdaterErrorInvalidServerResponse = 5;
const NSInteger SQRLUpdaterErrorInvalidJSON = 6;
const NSInteger SQRLUpdaterErrorInvalidServerBody = 7;

// The prefix used when creating temporary directories for updates. This will be
// followed by a random string of characters.
static NSString * const SQRLUpdaterUniqueTemporaryDirectoryPrefix = @"update.";

@interface SQRLUpdater ()

@property (atomic, readwrite) SQRLUpdaterState state;

// Parses an update model from downloaded data.
//
// data - JSON data representing an update manifest. This must not be nil.
//
// Returns a signal which synchronously sends a `SQRLUpdate` then completes, or
// errors.
- (RACSignal *)updateFromJSONData:(NSData *)data;

@end

@implementation SQRLUpdater

#pragma mark Properties

- (RACSignal *)updates {
	return [[self.checkForUpdatesCommand.executionSignals
		concat]
		setNameWithFormat:@"%@ -updates", self];
}

#pragma mark Lifecycle

- (id)init {
	NSAssert(NO, @"Use -initWithUpdateRequest: instead");
	return nil;
}

- (id)initWithUpdateRequest:(NSURLRequest *)updateRequest {
	NSParameterAssert(updateRequest != nil);

	self = [super init];
	if (self == nil) return nil;

	_updateRequest = [updateRequest copy];
	_updateClass = SQRLUpdate.class;

	BOOL updatesDisabled = (getenv("DISABLE_UPDATE_CHECK") != NULL);
	@weakify(self);

	_checkForUpdatesCommand = [[RACCommand alloc] initWithEnabled:[RACSignal return:@(!updatesDisabled)] signalBlock:^(id _) {
		@strongify(self);
		NSParameterAssert(self.updateRequest != nil);

		// TODO: Maybe allow this to be an argument to the command?
		NSMutableURLRequest *request = [self.updateRequest mutableCopy];
		[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

		// Prune old updates before the first update check.
		return [[[[[RACSignal defer:^RACSignal *{
				self.state = SQRLUpdaterStateCheckingForUpdate;

				return [NSURLConnection rac_sendAsynchronousRequest:request];
			}]
			reduceEach:^(NSURLResponse *response, NSData *bodyData) {
				if ([response isKindOfClass:NSHTTPURLResponse.class]) {
					NSHTTPURLResponse *httpResponse = (id)response;
					if (!(httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299)) {
						NSDictionary *errorInfo = @{
							NSLocalizedDescriptionKey: NSLocalizedString(@"Update check failed", nil),
							NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"The server sent an invalid response. Try again later.", nil),
							SQRLUpdaterServerDataErrorKey: bodyData,
						};
						NSError *error = [NSError errorWithDomain:SQRLUpdaterErrorDomain code:SQRLUpdaterErrorInvalidServerResponse userInfo:errorInfo];
						return [RACSignal error:error];
					}

					if (httpResponse.statusCode == 204 /* No Content */) {
						return [RACSignal empty];
					}
				}

				return [RACSignal return:bodyData];
			}]
			flatten]
			flattenMap:^(NSData *data) {
				return [[self updateFromJSONData:data] doCompleted:^{
					self.state = SQRLUpdaterStateIdle;
				}];
			}]
			deliverOn:RACScheduler.mainThreadScheduler];
	}];


	return self;
}

#pragma mark Checking for Updates

- (RACDisposable *)startAutomaticChecksWithInterval:(NSTimeInterval)interval {
	@weakify(self);

	return [[[[[RACSignal
		interval:interval onScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground]]
		flattenMap:^(id _) {
			@strongify(self);
			return [[self.checkForUpdatesCommand
				execute:RACUnit.defaultUnit]
				catch:^(NSError *error) {
					NSLog(@"Error checking for updates: %@", error);
					return [RACSignal empty];
				}];
		}]
		takeUntil:self.rac_willDeallocSignal]
		publish]
		connect];
}

- (RACSignal *)updateFromJSONData:(NSData *)data {
	NSParameterAssert(data != nil);

	return [[RACSignal
		defer:^{
			NSError *error = nil;
			NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
			if (JSON == nil) {
				NSMutableDictionary *userInfo = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
				userInfo[NSLocalizedDescriptionKey] = NSLocalizedString(@"Update check failed", nil);
				userInfo[NSLocalizedRecoverySuggestionErrorKey] = NSLocalizedString(@"The server sent an invalid response. Try again later.", nil);
				userInfo[SQRLUpdaterServerDataErrorKey] = data;
				if (error != nil) userInfo[NSUnderlyingErrorKey] = error;

				return [RACSignal error:[NSError errorWithDomain:SQRLUpdaterErrorDomain code:SQRLUpdaterErrorInvalidServerBody userInfo:userInfo]];
			}

			Class updateClass = self.updateClass;
			NSAssert([updateClass isSubclassOfClass:SQRLUpdate.class], @"%@ is not a subclass of SQRLUpdate", updateClass);

			SQRLUpdate *update = nil;
			error = nil;
			if ([JSON isKindOfClass:NSDictionary.class]) update = [MTLJSONAdapter modelOfClass:updateClass fromJSONDictionary:JSON error:&error];

			if (update == nil) {
				NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
				userInfo[NSLocalizedDescriptionKey] = NSLocalizedString(@"Update check failed", nil);
				userInfo[NSLocalizedRecoverySuggestionErrorKey] = NSLocalizedString(@"The server sent an invalid JSON response. Try again later.", nil);
				userInfo[SQRLUpdaterJSONObjectErrorKey] = JSON;
				if (error != nil) userInfo[NSUnderlyingErrorKey] = error;

				return [RACSignal error:[NSError errorWithDomain:SQRLUpdaterErrorDomain code:SQRLUpdaterErrorInvalidJSON userInfo:userInfo]];
			}

			return [RACSignal return:update];
		}]
		setNameWithFormat:@"%@ -updateFromJSONData:", self];
}

@end
