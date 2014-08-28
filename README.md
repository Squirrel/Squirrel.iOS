# Squirrel

Squirrel is an iOS framework focused on making enterprise application
distribution as safe and transparent as updates to a website.

Instead of publishing a feed of versions from which your app must select,
Squirrel updates to the version your server tells it to. This allows you to
intelligently update your clients based on the request you give to Squirrel.

Your request can include authentication details, custom headers or a request
body so that your server has the context it needs in order to supply the most
suitable update.

The update JSON Squirrel requests should be dynamically generated based on
criteria in the request, and whether an update is required. Squirrel relies on
server side support for determining whether an update is required, see [Server
Support](#server-support).

# Configuration

```objc
#import <Squirrel/Squirrel.h>

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSURLComponents *components = [[NSURLComponents alloc] init];

    components.scheme = @"http";
    components.host = @"mycompany.com";
    components.path = @"/myapp/latest";

    NSString *bundleVersion = NSBundle.mainBundle.sqrl_bundleVersion;
    components.query = [[NSString stringWithFormat:@"version=%@", bundleVersion] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]

    self.updater = [[SQRLUpdater alloc] initWithUpdateRequest:[NSURLRequest requestWithURL:components.URL]];

    // Check for updates every 4 hours.
    [self.updater startAutomaticChecksWithInterval:60 * 60 * 4];
}
```

Squirrel will periodically request and automatically download any updates. When
your application terminates, any downloaded update will be automatically
installed.

## Update Requests

Squirrel is indifferent to the request the client application provides for
update checking. `Accept: application/json` is added to the request headers
because Squirrel is responsible for parsing the response.

For the requirements imposed on the responses and the body format of an update
response see [Server Support](#server-support).

Your update request must *at least* include a version identifier so that the
server can determine whether an update for this specific version is required. It
may also include other identifying criteria such as operating system version or
username, to allow the server to deliver as fine grained an update as you
would like.

How you include the version identifier or other criteria is specific to the
server that you are requesting updates from. A common approach is to use query
parameters, [Configuration](#configuration) shows an example of this.

# Server Support

Your server should determine whether an update is required based on the
[Update Request](#update-requests) your client issues.

If an update is required your server should respond with a status code of
[200 OK](http://tools.ietf.org/html/rfc2616#section-10.2.1) and include the
[update JSON](#update-json-format) in the body. Squirrel **will** download and
install this update, even if the version of the update is the same as the
currently running version. To save redundantly downloading the same version
multiple times your server must not inform the client to update.

If no update is required your server must respond with a status code of
[204 No Content](http://tools.ietf.org/html/rfc2616#section-10.2.5). Squirrel
will check for an update again at the interval you specify.

## Update JSON Format

When an update is available, Squirrel expects the following schema in response
to the update request provided:

```json
{
    "url": "http://mycompany.com/myapp/releases/myrelease",
    "name": "My Release Name",
    "notes": "Theses are some release notes innit",
    "pub_date": "2013-09-18T12:29:53+01:00",
}
```

# User Interface

Squirrel does not provide any GUI components for presenting updates. If you want
to indicate updates to the user, make sure to [listen for downloaded updates
](#update-notifications).
