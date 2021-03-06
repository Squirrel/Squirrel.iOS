//
//  SQRLUpdater.h
//  Squirrel
//
//  Created by Justin Spahr-Summers on 2013-07-21.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

// Represents the current state of the updater.
//
// SQRLUpdaterStateIdle              - Doing absolutely diddly squat.
// SQRLUpdaterStateCheckingForUpdate - Checking for any updates from the server.
typedef enum : NSUInteger {
       SQRLUpdaterStateIdle,
       SQRLUpdaterStateCheckingForUpdate
} SQRLUpdaterState;

// The domain for errors originating within SQRLUpdater.
extern NSString * const SQRLUpdaterErrorDomain;

// The downloaded update does not contain an app bundle, or it was deleted on
// disk before we could get to it.
extern const NSInteger SQRLUpdaterErrorMissingUpdateBundle;

// An error occurred in the out-of-process updater while it was setting up.
extern const NSInteger SQRLUpdaterErrorPreparingUpdateJob;

// The code signing requirement for the running application could not be
// retrieved.
extern const NSInteger SQRLUpdaterErrorRetrievingCodeSigningRequirement;

// The server sent a response that we didn't understand.
//
// Includes `SQRLUpdaterServerDataErrorKey` in the error's `userInfo`.
extern const NSInteger SQRLUpdaterErrorInvalidServerResponse;

// The server sent a response body that we didn't understand.
//
// Includes `SQRLUpdaterServerDataErrorKey` in the error's `userInfo`.
extern const NSInteger SQRLUpdaterErrorInvalidServerBody;

// The server sent update JSON that we didn't understand.
//
// Includes `SQRLUpdaterJSONObjectErrorKey` in the error's `userInfo`.
extern const NSInteger SQRLUpdaterErrorInvalidJSON;

// Associated with the `NSData` received from the server when an error with code
// `SQRLUpdaterErrorInvalidServerResponse` is generated.
extern NSString * const SQRLUpdaterServerDataErrorKey;

// Associated with the JSON object that was received from the server when an
// error with code `SQRLUpdaterErrorInvalidJSON` is generated.
extern NSString * const SQRLUpdaterJSONObjectErrorKey;

@class RACCommand;
@class RACDisposable;
@class RACSignal;

// Checks for, downloads, and installs updates.
@interface SQRLUpdater : NSObject

// Kicks off a check for updates.
//
// If an update is available, it will be sent on `updates` once downloaded.
@property (nonatomic, strong, readonly) RACCommand *checkForUpdatesCommand;

// The current state of the manager.
//
// This property is KVO-compliant.
@property (atomic, readonly) SQRLUpdaterState state;

// Sends an `SQRLDownloadedUpdate` object on the main thread whenever a new
// update is available.
//
// This signal is actually just `checkForUpdatesCommand.executionSignals`,
// flattened for convenience.
@property (nonatomic, strong, readonly) RACSignal *updates;

// The request that will be sent to check for updates.
//
// The default value is the argument that was originally passed to
// -initWithUpdateRequest:.
//
// This property must never be set to nil.
@property (atomic, copy) NSURLRequest *updateRequest;

// The `SQRLUpdate` subclass to instantiate with the server's response.
//
// By default, this is `SQRLUpdate` itself, but it can be set to a custom
// subclass in order to preserve additional JSON data. See the `SQRLUpdate`
// documentation for more information.
@property (atomic, strong) Class updateClass;

// Initializes an updater that will send the given request to check for updates.
//
// This is the designated initializer for this class.
//
// updateRequest - A request to send to check for updates. This request can be
//                 customized as desired, like by including an `Authorization`
//                 header to authenticate with a private update server, or
//                 pointing to a local URL for testing. This must not be nil.
//
// Returns the initialized `SQRLUpdater`.
- (id)initWithUpdateRequest:(NSURLRequest *)updateRequest;

// Executes `checkForUpdatesCommand` (if enabled) every `interval` seconds.
//
// The first check will not occur until `interval` seconds have passed.
//
// interval - The interval, in seconds, between each check.
//
// Returns a disposable which can be used to cancel the automatic update
// checking.
- (RACDisposable *)startAutomaticChecksWithInterval:(NSTimeInterval)interval;

@end

@interface SQRLUpdater (Unavailable)

- (id)init __attribute__((unavailable("Use -initWithUpdateRequest: instead")));

@end
