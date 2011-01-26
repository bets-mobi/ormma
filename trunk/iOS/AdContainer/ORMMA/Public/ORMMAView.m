//
//  TWCRichAdView.m
//  RichMediaAds
//
//  Created by Robert Hedin on 9/7/10.
//  Copyright 2010 The Weather Channel. All rights reserved.
//

#import <EventKit/EventKit.h>
#import "ORMMAView.h"
#import "UIDevice-Hardware.h"
#import "UIDevice-ORMMA.h"
#import "UIWebView-ORMMA.h"
#import "ORMMAJavascriptBridge.h"
#import "ORMMALocalServer.h"
#import "ORMMAWebBrowserViewController.h"


@interface ORMMAView () <UIWebViewDelegate,
						 ORMMAJavascriptBridgeDelegate,
						 ORMMALocalServerDelegate>

@property( nonatomic, retain, readwrite ) NSError *lastError;
@property( nonatomic, assign, readwrite ) ORMMAViewState currentState;
@property( nonatomic, retain ) ORMMAWebBrowserViewController *webBrowser;
@property( nonatomic, assign, readwrite ) BOOL isOrmmaAd;
@property( nonatomic, retain ) NSURL *launchURL;

- (void)commonInitialization;

- (NSInteger)angleFromOrientation:(UIDeviceOrientation)orientation;

+ (void)copyFile:(NSString *)file
		  ofType:(NSString *)type
	  fromBundle:(NSBundle *)bundle
		  toPath:(NSString *)path;

- (void)blockingViewTouched:(id)sender;

- (void)logFrame:(CGRect)frame
			text:(NSString *)text;

- (NSString *)usingWebView:(UIWebView *)webView
		 executeJavascript:(NSString *)javascript
			   withVarArgs:(va_list)varargs;


- (void)injectJavaScriptIntoWebView:(UIWebView *)webView;
- (void)injectORMMAJavaScriptIntoWebView:(UIWebView *)webView;
- (void)injectORMMAStateIntoWebView:(UIWebView *)webView;
- (void)injectJavaScriptFile:(NSString *)fileName
				 intoWebView:(UIWebView *)webView;

- (void)fireAdWillShow;
- (void)fireAdDidShow;
- (void)fireAdWillHide;
- (void)fireAdDidHide;
- (void)fireAdWillClose;
- (void)fireAdDidClose;
- (void)fireAdWillResizeToSize:(CGSize)size;
- (void)fireAdDidResizeToSize:(CGSize)size;
- (void)fireAdWillExpandToFrame:(CGRect)frame;
- (void)fireAdDidExpandToFrame:(CGRect)frame;
- (void)fireAppShouldSuspend;
- (void)fireAppShouldResume;


-(void)verifyAppStoreLaunchWithURL:(NSURL*)url;

@end




@implementation ORMMAView


#pragma mark -
#pragma mark Statics

static ORMMALocalServer *s_localServer;
static NSBundle *s_ormmaBundle;


#pragma mark -
#pragma mark Constants

NSString * const kAnimationKeyExpand = @"expand";
NSString * const kAnimationKeyCloseExpanded = @"closeExpanded";

NSString * const kInitialORMMAPropertiesFormat = @"{ state: '%@'," \
												   " network: '%@',"\
												   " size: { width: %f, height: %f },"\
												   " maxSize: { width: %f, height: %f },"\
												   " screenSize: { width: %f, height: %f },"\
												   " defaultPosition: { x: %f, y: %f, width: %f, height: %f },"\
												   " orientation: %i,"\
												   " supports: [ 'level-1', 'level-2', 'orientation', 'network', 'screen', 'shake', 'size', 'tilt'%@ ] }";


#pragma mark -
#pragma mark Properties

@synthesize ormmaDelegate = m_ormmaDelegate;
@dynamic htmlStub;
@synthesize creativeURL = m_creativeURL;
@synthesize lastError = m_lastError;
@synthesize currentState = m_currentState;
@synthesize maxSize = m_maxSize;
@synthesize webBrowser = m_webBrowser;

@synthesize allowLocationServices = m_allowLocationServices;

@synthesize isOrmmaAd = m_isOrmmaAd;
@synthesize launchURL = m_launchURL;


#pragma mark -
#pragma mark Initializers / Memory Management

+ (void)initialize
{
	// setup autorelease pool since this will be called outside of one
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// setup our cache
	s_localServer = [ORMMALocalServer sharedInstance];
	
	// access our bundle
	NSString *path = [[NSBundle mainBundle] pathForResource:@"ORMMA"
													 ofType:@"bundle"];
	if ( path == nil )
	{
		[NSException raise:@"Invalid Build Detected"
					format:@"Unable to find ORMMA.bundle. Make sure it is added to your resources!"];
	} 
	s_ormmaBundle = [[NSBundle bundleWithPath:path] retain];
	
	// load the Public Javascript API
	path = [ORMMALocalServer rootDirectory];
	[self copyFile:@"ormma"
			ofType:@"js" 
		fromBundle:s_ormmaBundle 
			toPath:path];
	
	// load the Native Javascript API
	[self copyFile:@"ormma-ios-bridge"
			ofType:@"js" 
		fromBundle:s_ormmaBundle 
			toPath:path];
	
	// done with autorelease pool
	[pool drain];
}


- (id)initWithCoder:(NSCoder *)coder
{
    if ( ( self = [super initWithCoder:coder] ) ) 
	{
		[self commonInitialization];
	}
	return self;
}


- (id)initWithFrame:(CGRect)frame 
{
    if ( ( self = [super initWithFrame:frame] ) ) 
    {
		[self commonInitialization];
    }
    return self;
}


- (void)commonInitialization
{
	// create our bridge object
	m_javascriptBridge = [[ORMMAJavascriptBridge alloc] init];
	m_javascriptBridge.bridgeDelegate = self;
	
	// it's up to the client to set any resizing policy for this container
	
	// make sure our default background color is transparent,
	// the consumer can change it if need be
	self.backgroundColor = [UIColor clearColor];
	self.opaque = NO;
	
	// let's create a webview that will fill it's parent
	CGRect webViewFrame = CGRectMake( 0, 
									  0, 
									  self.frame.size.width, 
									  self.frame.size.height );
	m_webView = [[UIWebView alloc] initWithFrame:webViewFrame];
	[m_webView disableBounces];
	
	// make sure the webview will expand/contract as needed
	m_webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | 
								 UIViewAutoresizingFlexibleHeight;
	m_webView.clipsToBounds = YES;

	// register ourselves to recieve any delegate calls
	m_webView.delegate = self;
	
	// the web view should be transparent
	m_webView.backgroundColor = [UIColor clearColor];
	m_webView.opaque = NO;
	
	// add the web view to the main view
	[self addSubview:m_webView];
	
	// let the OS know that we care about receiving various notifications
	m_currentDevice = [UIDevice currentDevice];
	[m_currentDevice beginGeneratingDeviceOrientationNotifications];
	m_currentDevice.proximityMonitoringEnabled = NO; // enable as-needed to conserve power
	
	// setup default maximum size based on our current frame size
	self.maxSize = self.frame.size;
	
	// set our initial state
	self.currentState = ORMMAViewStateDefault;
	
	// setup special protocols
	m_externalProtocols = [[NSMutableArray alloc] init];
}


- (void)dealloc 
{
	// we're done receiving device changes
	[m_currentDevice endGeneratingDeviceOrientationNotifications];

	// free up some memory
	[m_creativeURL release], m_creativeURL = nil;
	m_currentDevice = nil;
	[m_lastError release], m_lastError = nil;
	[m_webView release], m_webView = nil;
	[m_blockingView release], m_blockingView = nil;
	m_ormmaDelegate = nil;
	[m_javascriptBridge restoreServicesToDefaultState], [m_javascriptBridge release], m_javascriptBridge = nil;
	[m_webBrowser release], m_webBrowser = nil;
	[m_launchURL release], m_launchURL = nil;
	[m_externalProtocols removeAllObjects], [m_externalProtocols release], m_externalProtocols = nil;
    [super dealloc];
}




#pragma mark -
#pragma mark Dynamic Properties

- (NSString *)htmlStub
{
	// delegate to cache
	ORMMALocalServer *cache = [ORMMALocalServer sharedInstance];
	return cache.htmlStub;
}


- (void)setHtmlStub:(NSString *)stub
{
	// delegate to cache
	ORMMALocalServer *cache = [ORMMALocalServer sharedInstance];
	cache.htmlStub = stub;
}
		 


#pragma mark -
#pragma mark UIWebViewDelegate Methods

- (void)webView:(UIWebView *)webView 
didFailLoadWithError:(NSError *)error
{
	NSLog( @"Failed to load URL into Web View: %@", error );
	self.lastError = error;
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(failureLoadingAd:)] ) )
	{
		[self.ormmaDelegate failureLoadingAd:self];
	}
	m_loadingAd = NO;
}


- (BOOL)webView:(UIWebView *)webView 
shouldStartLoadWithRequest:(NSURLRequest *)request 
 navigationType:(UIWebViewNavigationType)navigationType
{
	NSURL *url = [request URL];
	NSLog( @"Verify Web View should load URL: %@", url );

	if ( [request.URL isFileURL] )
	{
		// Direct access to the file system is disallowed
		return NO;
	}

	// handle iTunes requests
	NSString *fullUrl = [request.URL absoluteString];
	if ( ( [fullUrl rangeOfString:@"://itunes.apple.com/"].length > 0 ) || 
		 ( [fullUrl rangeOfString:@"://phobos.apple.com/"].length > 0 ) )
	{
		NSLog( @"Treating URL %@ as call to app store", request.URL );
		[self verifyAppStoreLaunchWithURL:request.URL];
		return NO;
	}
	
	// normal ad
	if ( [m_javascriptBridge processURL:url
							 forWebView:webView] )
	{
		// the bridge processed the url, nothing else to do
		return NO;
	}
	if ( [@"about:blank" isEqualToString:fullUrl] )
	{
		// don't bother loading the empty page
		NSLog( @"IFrame Detected" );
		return NO;
	}
	
	// handle maps and mailto
	NSString *scheme = url.scheme;
	if ( [@"mailto" isEqualToString:scheme] )
	{
		// handle mail to
		NSLog( @"MAILTO: %@", url );
		NSString *addr = [url.absoluteString substringFromIndex:7];
		if ( [addr hasPrefix:@"//"] )
		{
			NSString *addr = [addr substringFromIndex:2];
		}
		
		[self sendEMailTo:addr
			  withSubject:nil
				 withBody:nil
				   isHTML:NO];
		
		return NO;
	}
	else if ( [@"tel" isEqualToString:scheme] )
	{
		// handle telephone call
		UIApplication *app = [UIApplication sharedApplication];
		[app openURL:url];
		return NO;
	}
	else if ( [@"http" isEqualToString:scheme] )
	{
		// handle special cased URLs
		if ( [@"maps.google.com" isEqualToString:url.host] )
		{
			// handle google maps
			UIApplication *app = [UIApplication sharedApplication];
			[app openURL:url];
			return NO;
		}
	}
	
	// not handled by ORMMA, see if the delegate wants it
	if ( m_externalProtocols.count > 0 )
	{
		if ( [self.ormmaDelegate respondsToSelector:@selector(handleRequest:forAd:)] )
		{
			NSLog( @"Scheme is: %@", scheme );
			for ( NSString *p in m_externalProtocols )
			{
				if ( [p isEqualToString:scheme] )
				{
					// container handles the call
					[self.ormmaDelegate handleRequest:request
												forAd:self];
					NSLog( @"Container handled request for: %@", request );
					return NO;
				}
			}
		}
	}
	
	// if the user clicked a non-handled link, open it in a new browser
	if ( !m_loadingAd )
	{
		NSLog( @"Delegating Open to web browser." );

		[self fireAppShouldSuspend];
		
		if ( self.currentState == ORMMAViewStateExpanded )
		{
			self.hidden = YES;
			m_blockingView.hidden = YES;
		}

		ORMMAWebBrowserViewController *wbvc = [ORMMAWebBrowserViewController ormmaWebBrowserViewController];
		wbvc.URL = request.URL;
		wbvc.browserDelegate = self;
		UIViewController *vc = [self.ormmaDelegate ormmaViewController];
		[vc presentModalViewController:wbvc
							  animated:YES];
		return NO;
	}
	
	// for all other cases, just let the web view handle it
	NSLog( @"Perform Normal process for URL." );
	return YES;
}


- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	// we've finished loading the URL
	[self injectJavaScriptIntoWebView:webView];
	[m_webView disableBounces];
	m_loadingAd = NO;
}


- (void)webViewDidStartLoad:(UIWebView *)webView
{
	NSLog( @"Web View Started Loading" );
}


#pragma mark -
#pragma mark Ad Loading

- (void)loadCreative:(NSURL *)url
{
	// reset our state
	m_applicationReady = NO;
	
	[self restoreToDefaultState];
	
	// ads loaded by URL are assumed to be complete as-is, just display it
	NSLog( @"Load Ad from URL: %@", url );
	self.creativeURL = url;
	[s_localServer cacheURL:url
			   withDelegate:self];
}


- (void)loadHTMLCreative:(NSString *)htmlFragment
			 creativeURL:(NSURL *)url
{
	// reset our state
	m_applicationReady = NO;
	
	[self restoreToDefaultState];
	
	self.creativeURL = url;
	[s_localServer cacheHTML:htmlFragment
					 baseURL:url
				withDelegate:self];
}



#pragma mark -
#pragma mark External Protocol Control

- (void)registerProtocol:(NSString *)protocol
{
	// don't allow dupes
	for ( NSString *p in m_externalProtocols )
	{
		if ( [p isEqualToString:protocol] )
		{
			// already present, ignore
			return;
		}
	}
	
	// not yet present, add it
	[m_externalProtocols addObject:protocol];
}


- (void)deregisterProtocol:(NSString *)protocol
{
	for ( NSInteger i = ( m_externalProtocols.count - 1 ); i >= 0; i-- )
	{
		NSString *p = [m_externalProtocols objectAtIndex:i];
		if ( [p isEqualToString:protocol] )
		{
			// found a match, remove it
			[m_externalProtocols removeObjectAtIndex:i];
		}
	}
}



#pragma mark -
#pragma mark External Ad Size Control

- (void)restoreToDefaultState
{
	if ( self.currentState != ORMMAViewStateDefault )
	{
		[self closeAd:m_webView];
	}
}



#pragma mark -
#pragma mark Javascript Bridge Delegate
- (UIWebView *)webView
{
	return m_webView;
}


- (void)adIsORMMAEnabledForWebView:(UIWebView *)webView
{
	self.isOrmmaAd = YES;
}


- (NSString *)usingWebView:(UIWebView *)webView
		 executeJavascript:(NSString *)javascript, ...
{
	// handle variable argument list
	va_list args;
	va_start( args, javascript );
	NSString *result = [self usingWebView:webView
						executeJavascript:javascript
							  withVarArgs:args];
	va_end( args );
	return result;
}


- (NSString *)usingWebView:(UIWebView *)webView
		 executeJavascript:(NSString *)javascript
			   withVarArgs:(va_list)args
{
	NSString *js = [[[NSString alloc] initWithFormat:javascript arguments:args] autorelease];
	NSLog( @"Executing Javascript: %@", js );
	return [webView stringByEvaluatingJavaScriptFromString:js];
}


- (void)showAd:(UIWebView *)webView
{
	// called when the ad needs to be made visible
	[self fireAdWillShow];
	
	// Nothing special to do, other than making sure the ad is visible
	NSString *newState = @"default";
	self.currentState = ORMMAViewStateDefault;
	
	// notify that we're done
	[self fireAdDidShow];
	
	// notify the ad view that the state has changed
	[self usingWebView:webView
	executeJavascript:@"window.ormmaview.fireChangeEvent( { state: '%@' } );", newState];
}


- (void)hideAd:(UIWebView *)webView
{
	// make sure we're not already hidden
	if ( self.currentState == ORMMAViewStateHidden )
	{
		[self usingWebView:webView
		 executeJavascript:@"window.ormmaview.fireErrorEvent( 'Cannot hide if we're already hidden.', 'hide' );" ]; 
		return;
	}	
	
	// called when the ad is ready to hide
	[self fireAdWillHide];
	
	// if the ad isn't in the default state, restore it first
	[self closeAd:webView];
	
	// now hide the ad
	self.hidden = YES;
	self.currentState = ORMMAViewStateHidden;

	// notify everyone that we're done
	[self fireAdDidHide];
	
	// notify the ad view that the state has changed
	[self usingWebView:webView
	 executeJavascript:@"window.ormmaview.fireChangeEvent( { state: 'hidden', size: { width: 0, height: 0 } } );"];
}


- (void)closeAd:(UIWebView *)webView
{
	// reality check
	NSAssert( ( webView != nil ), @"Web View passed to close is NULL" );
	
	// if we're in the default state already, there is nothing to do
	if ( self.currentState == ORMMAViewStateDefault )
	{
		// default ad, nothing to do
		return;
	}
	if ( self.currentState == ORMMAViewStateHidden )
	{
		// hidden ad, nothing to do
		return;
	}
	
	// Closing the ad refers to restoring the default state, whatever tasks
	// need to be taken to achieve this state
	
	// notify the app that we're starting
	[self fireAdWillClose];
	
	// closing the ad differs based on the current state
	if ( self.currentState == ORMMAViewStateExpanded )
	{
		// We know we're going to close our state from the expanded state.
		// So we basically want to reverse the steps we took to get to the
		// expanded state as follows: (note: we already know we're in a good
		// state to close)
		//
		// so... here's what we're going to do:
		// step 1: start a new animation, and change our frame
		// step 2: change our frame to the stored translated frame
		// step 3: wait for the animation to complete
		// step 4: restore our frame to the original untranslated frame
		// step 5: get a handle to the key window
		// step 6: get a handle to the previous parent view based on the tag
		// step 7: restore the parent view's original tag
		// step 8: add ourselves to the original parent window
		// step 9: remove the blocking view
		// step 10: fire the size changed ORMMA event
		// step 11: update the state to default
		// step 12: fire the state changed ORMMA event
		// step 13: fire the application did close delegate call
		//
		// Now, let's get started
		
		// step 1: start a new animation, and change our frame
		// step 2: change our frame to the stored translated frame
		[UIView beginAnimations:kAnimationKeyCloseExpanded
						context:nil];
		[UIView setAnimationDuration:0.5];
		[UIView setAnimationDelegate:self];

		// step 2: change our frame to the stored translated frame
		self.frame = m_translatedFrame;

		// update the web view as well
		CGRect webFrame = CGRectMake( 0, 0, m_translatedFrame.size.width, m_translatedFrame.size.height );
		webView.frame = webFrame;
		
		[UIView commitAnimations];

		// step 3: wait for the animation to complete
		// (more happens after the animation completes)
    }
	else
	{
		// animations for resize are delegated to the application
		
		// notify the app that we are resizing
		[self fireAdWillResizeToSize:m_defaultFrame.size];
		
		// restore the size
		self.frame = m_defaultFrame;
		
		// update the web view as well
		CGRect webFrame = CGRectMake( 0, 0, m_defaultFrame.size.width, m_defaultFrame.size.height );
		webView.frame = webFrame;
		
		// notify the app that we are resizing
		[self fireAdDidResizeToSize:m_defaultFrame.size];
		
		// notify the app that we're done
		[self fireAdDidClose];
		
		// update our state
		self.currentState = ORMMAViewStateDefault;
		
		// notify the client
		[self usingWebView:webView
		 executeJavascript:@"window.ormmaview.fireChangeEvent( { state: 'default', size: { width: %f, height: %f } } );", m_defaultFrame.size.width, m_defaultFrame.size.height ];
	}
}


- (void)expandTo:(CGRect)endingFrame
		 withURL:(NSURL *)url
	inWebView:(UIWebView *)webView
   blockingColor:(UIColor *)blockingColor
blockingOpacity:(CGFloat)blockingOpacity
{
	// OK, here's what we have to do when the creative want's to expand
	// Note that this is NOT the same as resize.
	// first, since we have no idea about the surrounding view hierarchy we
	// need to pull our container to the "top" of the view hierarchy. This
	// means that we need to be able to restore ourselves when we're done, so
	// we want to remember our settings from before we kick off the expand
	// function.
	//
	// so... here's what we're going to do:
	// step 0: make sure we're in a valid state to expand
	// step 1: fire the application will expand delegate call
	// step 2: get a handle to the key window
	// step 3: store the current frame for later re-use
	// step 4: create a blocking view that fills the current window
	// step 5: store the current tag for the parent view
	// step 6: pick a random unused tag
	// step 7: change the parent view's tag to the new random tag
	// step 8: create a new frame, based on the current frame but with
	//         coordinates translated to the window space
	// step 9: store this new frame for later use
	// step 10: change our frame to the new one
	// step 11: add ourselves to the key window
	// step 12: start a new animation, and change our frame
	// step 13: wait for the animation to complete
	// step 14: fire the size changed ORMMA event
	// step 15: update the state to expanded
	// step 16: fire the state changed ORMMA event
    // step 17: fire the application did expand delegate call
	//
	// Now, let's get started
	
	// step 0: make sure we're in a valid state to expand
	if ( self.currentState != ORMMAViewStateDefault )
	{
		// Already Expanded
		[self usingWebView:webView
		 executeJavascript:@"window.ormmaview.fireErrorEvent( 'Can only expand from the default state.', 'expand' );" ]; 
		return;
	}	
	 
	// step 1: fire the application will expand delegate call
	[self fireAdWillExpandToFrame:endingFrame];

	// step 2: get a handle to the key window
	UIApplication *app = [UIApplication sharedApplication];
	UIWindow *keyWindow = [app keyWindow];
	
	// step 3: store the current frame for later re-use
	m_defaultFrame = self.frame;
								
	// step 4: create a blocking view that fills the current window
	// if the status bar is visible, we need to account for it
	CGRect f = keyWindow.frame;
	UIApplication *a = [UIApplication sharedApplication];
	if ( !a.statusBarHidden )
	{
	   // status bar is visible
	   endingFrame.origin.y -= 20;
	}
	if ( m_blockingView != nil )
	{
		[m_blockingView removeFromSuperview], m_blockingView = nil;
	}
	m_blockingView = [[UIView alloc] initWithFrame:f];
	m_blockingView.backgroundColor = blockingColor;
	m_blockingView.alpha = blockingOpacity;
	[keyWindow addSubview:m_blockingView];
	
	// step 5: store the current tag for the parent view
	UIView *parentView = self.superview;
	m_originalTag = parentView.tag;
	
	// step 6: pick a random unused tag
	m_parentTag = 0;
	do 
	{
		m_parentTag = arc4random() % 25000;
	} while ( [keyWindow viewWithTag:m_parentTag] != nil );
	
	// step 7: change the parent view's tag to the new random tag
	parentView.tag = m_parentTag;

	// step 8: create a new frame, based on the current frame but with
	//         coordinates translated to the window space
	// step 9: store this new frame for later use
	m_translatedFrame = [self convertRect:m_defaultFrame
								   toView:keyWindow];
	
	// step 10: change our frame to the new one
	self.frame = m_translatedFrame;
	
	// step 11: add ourselves to the key window
	[keyWindow addSubview:self];
	
	// step 12: start a new animation, and change our frame
	[UIView beginAnimations:kAnimationKeyExpand
					context:nil];
	[UIView setAnimationDuration:0.5];
	[UIView setAnimationDelegate:self];
	self.frame = endingFrame;

	// Create frame for web view
	CGRect webFrame = CGRectMake( 0, 0, endingFrame.size.width, endingFrame.size.height );
	webView.frame = webFrame;
	
	[UIView commitAnimations];
	
	// step 13: wait for the animation to complete
	// (more happens after the animation completes)
}


- (void)resizeToWidth:(CGFloat)width
			   height:(CGFloat)height
			inWebView:(UIWebView *)webView
{
	// resize must work within the view hierarchy; all the ORMMA ad view does
	// is modify the frame size while leaving the containing application to 
	// determine how this should be presented (animations).
	
	// note: we can only resize if we are in the default state and only to the
	//       limit specified by the maxSize value.
	
	// verify that we can resize
	if ( m_currentState != ORMMAViewStateDefault )
	{
		// we can't resize an expanded ad
		[self usingWebView:webView
		 executeJavascript:@"window.ormmaview.fireErrorEvent( 'Cannot resize an ad that is not in the default state.', 'resize' );" ]; 
		return;
	}
	
	// Make sure the resize honors our limits
	if ( ( height > self.maxSize.height ) ||
		 ( width > self.maxSize.width ) ) 
	{
		// we can't resize outside our limits
		[self usingWebView:webView
		 executeJavascript:@"window.ormmaview.fireErrorEvent( 'Cannot resize an ad larger than allowed.', 'resize' );" ]; 
		return;
	}
	
	// store the original frame
	m_defaultFrame = CGRectMake( self.frame.origin.x, 
								 self.frame.origin.y,
								 self.frame.size.width,
								 self.frame.size.height );
	
	// determine the final frame
	CGSize size = { width, height };
	
	// notify the application that we are starting to resize
	[self fireAdWillResizeToSize:size];
	
	// now update the size
	CGRect newFrame = CGRectMake( self.frame.origin.x, 
								  self.frame.origin.y, 
								  width,
								  height );
	self.frame = newFrame;
	
	// resize the web view as well
	newFrame.origin.x = 0;
	newFrame.origin.y = 0;
    m_webView.frame = newFrame;
	
	// make sure we're on top of everything
	[self.superview bringSubviewToFront:self];
	
	// notify the application that we are done resizing
	[self fireAdDidResizeToSize:size];
	
	// update our state
	self.currentState = ORMMAViewStateResized;
	
	// send state changed event
	[self usingWebView:webView
	 executeJavascript:@"window.ormmaview.fireChangeEvent( { state: 'resized', size: { width: %f, height: %f } } );", width, height ];
}


- (void)sendEMailTo:(NSString *)to
		withSubject:(NSString *)subject
		   withBody:(NSString *)body
			 isHTML:(BOOL)html
{
	// make sure that we can send email
	if ( [MFMailComposeViewController canSendMail] )
	{
		MFMailComposeViewController *vc = [[[MFMailComposeViewController alloc] init] autorelease];
		if ( to != nil )
		{
			NSArray *recipients = [NSArray arrayWithObject:to];
			[vc setToRecipients:recipients];
		}
		if ( subject != nil )
		{
			[vc setSubject:subject];
		}
		if ( body != nil )
		{
			[vc setMessageBody:body 
						isHTML:html];
		}
		
		// if we're expanded, our view hierarchy is going to be strange
		// and the modal dialog may come up "under" the expanded web view
		// let's hide it while the modal is up
		if ( self.currentState == ORMMAViewStateExpanded )
		{
			self.hidden = YES;
			m_blockingView.hidden = YES;
		}
		
		// notify the app that it should stop work
		[self fireAppShouldSuspend];

		// display the modal dialog
		vc.mailComposeDelegate = self;
		[self.ormmaDelegate.ormmaViewController presentModalViewController:vc
																  animated:YES];
	}
	else
	{
		// email isn't setup, let the app decide what to do
		if ( [self.ormmaDelegate respondsToSelector:@selector(emailNotSetupForAd:)] )
		{
			[self.ormmaDelegate emailNotSetupForAd:self];
		}
	}	
}


- (void)sendSMSTo:(NSString *)to
		 withBody:(NSString *)body
{
	if ( NSClassFromString( @"MFMessageComposeViewController" ) != nil )
	{
		// SMS support does exist
		if ( [MFMessageComposeViewController canSendText] ) 
		{
			// device can
			MFMessageComposeViewController *vc = [[[MFMessageComposeViewController alloc] init] autorelease];
			vc.messageComposeDelegate = self;
			if ( to != nil )
			{
				NSArray *recipients = [NSArray arrayWithObject:to];
				vc.recipients = recipients;
			}
			if ( body != nil )
			{
				vc.body = body;
			}
			
			// if we're expanded, our view hierarchy is going to be strange
			// and the modal dialog may come up "under" the expanded web view
			// let's hide it while the modal is up
			if ( self.currentState == ORMMAViewStateExpanded )
			{
				self.hidden = YES;
				m_blockingView.hidden = YES;
			}
		
			// notify the app that it should stop work
			[self fireAppShouldSuspend];
			
			// now show the dialog
			[self.ormmaDelegate.ormmaViewController presentModalViewController:vc
																	   animated:YES];
		}
	}
}


- (void)placeCallTo:(NSString *)phoneNumber
{
	if ( [self.ormmaDelegate respondsToSelector:@selector(placePhoneCall:)] )
	{
		// consumer wants to deal with it
		[self.ormmaDelegate placePhoneCall:phoneNumber];
	}
	else
	{
		// handle internally
		NSString *urlString = [NSString stringWithFormat:@"tel:%@", phoneNumber];
		NSURL *url = [NSURL URLWithString:urlString];
		NSLog( @"Executing: %@", url );
		[[UIApplication sharedApplication] openURL:url]; 
	}
}


- (void)addEventToCalanderForDate:(NSDate *)date
						withTitle:(NSString *)title
						 withBody:(NSString *)body
{
	if ( [self.ormmaDelegate respondsToSelector:@selector(createCalendarEntryForDate:title:body:)] )
	{
		// consumer wants to deal with it
		[self.ormmaDelegate createCalendarEntryForDate:date
												 title:title
												  body:body];
	}
	else
	{
		// handle internally
		EKEventStore *eventStore = [[EKEventStore alloc] init];
		
		EKEvent *event  = [EKEvent eventWithEventStore:eventStore];
		event.title = title;
		event.notes = body;
		
		event.startDate = date;
		event.endDate   = [[NSDate alloc] initWithTimeInterval:600 
													 sinceDate:event.startDate];
		
		NSError *err;
		[event setCalendar:[eventStore defaultCalendarForNewEvents]];
		[eventStore saveEvent:event 
						 span:EKSpanThisEvent 
						error:&err];       
	}
}


- (CGRect)getAdFrameInWindowCoordinates
{
	CGRect frame = [self convertRect:self.frame toView:self.window];
	return frame;
}


- (void)openBrowser:(UIWebView *)webView
	  withUrlString:(NSString *)urlString
		 enableBack:(BOOL)back
	  enableForward:(BOOL)forward
	  enableRefresh:(BOOL)refresh;
{
	// if the browser is already open, change the URL
	NSLog( @"Open Browser" );
	NSURL *url = [NSURL URLWithString:urlString];
	if ( self.webBrowser != nil )
	{
		// Redirect
		NSLog( @"Redirecting browser to new URL: %@", urlString );
		self.webBrowser.URL = url;
		return;
	}
	
	// notify the app that it should stop work
	[self fireAppShouldSuspend];
	
	// if the expanded view is on screen, hide it so we don't interfere with the full screen
	if ( self.currentState == ORMMAViewStateExpanded )
	{
	   self.hidden = YES;
	   m_blockingView.hidden = YES;
	}

	// display the web browser
	NSLog( @"Create Web Browser" );
	self.webBrowser = [ORMMAWebBrowserViewController ormmaWebBrowserViewController];
	NSLog( @"Web Browser created: %@", self.webBrowser );
	self.webBrowser.browserDelegate = self;
	self.webBrowser.backButtonEnabled = back;
	self.webBrowser.forwardButtonEnabled = forward;
	self.webBrowser.refreshButtonEnabled = refresh;
	BOOL safariEnabled = [self.ormmaDelegate respondsToSelector:@selector(showURLFullScreen:)];
	self.webBrowser.safariButtonEnabled = safariEnabled;
	self.webBrowser.URL = url;
	[self.ormmaDelegate.ormmaViewController presentModalViewController:self.webBrowser
															   animated:YES];
}


#pragma mark -
#pragma mark Web Browser Control

- (void)doneWithBrowser
{
	NSLog( @"Dismissing Browser" );
	[self.ormmaDelegate.ormmaViewController dismissModalViewControllerAnimated:YES];
	self.webBrowser = nil;
	
	// if the expanded view should be visible, make it so
	if ( self.currentState == ORMMAViewStateExpanded )
	{
		self.hidden = NO;
		m_blockingView.hidden = NO;
	}
	
	// called when the ad needs to be made visible
	[self fireAdWillShow];
	
	// notify the app that it should start work
	[self fireAppShouldResume];
	
	// called when the ad needs to be made visible
	[self fireAdDidShow];
}


- (void)showURLFullScreen:(NSURL *)url
			   sourceView:(UIView *)view
{
	// we want to give the user the opportunity to launch in safari
	if ( [self.ormmaDelegate respondsToSelector:@selector(showURLFullScreen:sourceView:)] )
	{
		[self.ormmaDelegate showURLFullScreen:url
								   sourceView:view];
	}
}


#pragma mark -
#pragma mark Animation View Delegate

- (void)animationDidStop:(NSString *)animationID 
				finished:(NSNumber *)finished 
				 context:(void *)context
{
	if ( [animationID isEqualToString:kAnimationKeyCloseExpanded] )
	{
		// finish the close expanded function
		// step 4: restore our frame to the original untranslated frame
		self.frame = m_defaultFrame;
		
		// step 5: get a handle to the key window
		UIApplication *app = [UIApplication sharedApplication];
		UIWindow *keyWindow = [app keyWindow];
		
		// step 6: get a handle to the previous parent view based on the tag
		UIView *parentView = [keyWindow viewWithTag:m_parentTag];
		
		// step 7: restore the parent view's original tag
		parentView.tag = m_originalTag;
		
		// step 8: add ourselves to the original parent window
		[parentView addSubview:self];
		
		// step 9: remove the blocking view
		[m_blockingView removeFromSuperview], m_blockingView = nil;
		
		// step 10: fire the size changed ORMMA event
		[self usingWebView:m_webView
		 executeJavascript:@"window.ormmaview.fireChangeEvent( { size: { width: %f, height: %f } } );", self.frame.size.width, self.frame.size.height ];
		
		// step 11: update the state to default
		self.currentState = ORMMAViewStateDefault;
		
		// step 12: fire the state changed ORMMA event
		[self usingWebView:m_webView
		 executeJavascript:@"window.ormmaview.fireChangeEvent( { state: 'default' } );" ];
		
		// step 13: fire the application did close delegate call
		[self fireAdDidClose];
	}
	else
	{
		// finish the expand function
		// step 14: fire the size changed ORMMA event
		[self usingWebView:m_webView
		 executeJavascript:@"window.ormmaview.fireChangeEvent( { size: { width: %f, height: %f } } );", self.frame.size.width, self.frame.size.height ];
		
		// step 15: update the state to expanded
		self.currentState = ORMMAViewStateExpanded;
		
		// step 16: fire the state changed ORMMA event
		[self usingWebView:m_webView
		 executeJavascript:@"window.ormmaview.fireChangeEvent( { state: 'expanded' } );" ];

		// step 17: fire the application did expand delegate call
		[self fireAdDidExpandToFrame:m_webView.frame];
	}
}



#pragma mark -
#pragma mark Cache Delegate

- (void)cacheFailed:(NSURL *)baseURL
		  withError:(NSError *)error
{
}


- (void)cachedCreative:(NSURL *)creativeURL
				 onURL:(NSURL *)url
				withId:(long)creativeId
{
	if ( [self.creativeURL isEqual:creativeURL] )
	{
		// now show the cached file
		m_creativeId = creativeId;
		NSURLRequest *request = [NSURLRequest requestWithURL:url];
		m_loadingAd = YES;
		[m_webView loadRequest:request];
		[m_webView disableBounces];
	}
}


- (void)cachedResource:(NSURL *)url
		   forCreative:(long)creativeId
{
	if ( creativeId == m_creativeId )
	{
		// TODO
	}
}


- (void)cachedResourceRetired:(NSURL *)url
				  forCreative:(long)creativeId
{
	// TODO
}


- (void)cachedResourceRemoved:(NSURL *)url
				  forCreative:(long)creativeId
{
	// TODO
}


// get JS to inject
- (NSString *)javascriptForInjection
{
	NSString *js = nil;
	if ( self.ormmaDelegate != nil )
	{
		if ( [self.ormmaDelegate respondsToSelector:@selector(javascriptForInjection)] )
		{
			js = [self.ormmaDelegate javascriptForInjection];
		}
	}
	return js;
}



#pragma mark -
#pragma mark Mail and SMS Composer Delegate

- (void)mailComposeController:(MFMailComposeViewController*)controller 
		  didFinishWithResult:(MFMailComposeResult)result 
						error:(NSError*)error
{
	// notify the app that it should stop work
	[self fireAppShouldResume];
	
	// close the dialog
	[self.ormmaDelegate.ormmaViewController dismissModalViewControllerAnimated:YES];
	
	// redisplay the expanded view if necessary
	self.hidden = NO;
	m_blockingView.hidden = NO;
}


- (void)messageComposeViewController:(MFMessageComposeViewController *)controller 
				 didFinishWithResult:(MessageComposeResult)result
{
	// notify the app that it should stop work
	[self fireAppShouldResume];
	
	// close the dialog
	[self.ormmaDelegate.ormmaViewController dismissModalViewControllerAnimated:YES];
	
	// redisplay the expanded view if necessary
	self.hidden = NO;
	m_blockingView.hidden = NO;
}


#pragma mark -
#pragma mark General Actions

- (void)blockingViewTouched:(id)sender
{
	// Restore the ad to it's default size
	[self closeAd:m_webView];
}



#pragma mark -
#pragma mark JavaScript Injection

- (void)injectJavaScriptIntoWebView:(UIWebView *)webView
{
	// notify app that the ad is preparing to show
	[self fireAdWillShow];
	
	// assume we are not an ORMMA ad until told otherwise
	NSString *test = [self usingWebView:webView executeJavascript:@"typeof ormmaview"];
	self.isOrmmaAd = ( [test isEqualToString:@"object"] );
	
	// always inject the ORMMA code
//	if ( self.isOrmmaAd )
//	{
		NSLog( @"Ad requires ORMMA, inject code" );
		[self injectORMMAJavaScriptIntoWebView:webView];
		
		// now allow the app to inject it's own javascript if needed
//		if ( self.ormmaDelegate != nil )
//		{
//			if ( [self.ormmaDelegate respondsToSelector:@selector(javascriptForInjection)] )
//			{
//				NSString *js = [self.ormmaDelegate javascriptForInjection];
//				[self usingWebView:webView executeJavascript:js];
//			}
//		}
		
		// now inject the current state
		[self injectORMMAStateIntoWebView:webView];
		
		// notify the creative that ORMMA is done
		m_applicationReady = YES;
		self.isOrmmaAd = YES;
//	}
	
	// Notify app that the ad has been shown
	[self fireAdDidShow];
}


- (void)injectORMMAJavaScriptIntoWebView:(UIWebView *)webView
{
//	NSLog( @"Injecting ORMMA Javascript into creative." );
//	if ( [self usingWebView:webView 
//		  executeJavascript:s_nativeAPI] == nil )
//	{
//		NSLog( @"Error injecting ORMMA Bridge Javascript!" );
//	}
//	if ( [self usingWebView:webView 
//		  executeJavascript:s_publicAPI] == nil )
//	{
//		NSLog( @"Error injecting ORMMA Public API Javascript!" );
//	}
}


- (void)injectJavaScriptFile:(NSString *)fileName
				 intoWebView:(UIWebView *)webView
{
	if ( [self usingWebView:webView 
		  executeJavascript:@"var ormmascr = document.createElement('script');ormmascr.src='%@';ormmascr.type='text/javascript';var ormmahd = document.getElementsByTagName('head')[0];ormmahd.appendChild(ormmascr);return 'OK';", fileName] == nil )
	{
		NSLog( @"Error injecting Javascript!" );
	}
}

- (void)injectORMMAStateIntoWebView:(UIWebView *)webView
{
	NSLog( @"Injecting ORMMA State into creative." );
	
	// setup the default state
	self.currentState = ORMMAViewStateDefault;
	[self fireAdWillShow];
	
	// add the various features the device supports
	NSMutableString *features = [NSMutableString stringWithCapacity:100];
	if ( [MFMailComposeViewController canSendMail] )
	{
		[features appendString:@", 'email'"]; 
	}
	if ( NSClassFromString( @"MFMessageComposeViewController" ) != nil )
	{
		// SMS support does exist
		if ( [MFMessageComposeViewController canSendText] ) 
		{
			[features appendString:@", 'sms'"]; 
		}
	}
	
	// allow LBS if app allows it
	if ( self.allowLocationServices )
	{
		[features appendString:@", 'location'"]; 
	}
	
	NSInteger platformType = [m_currentDevice platformType];
	switch ( platformType )
	{
		case UIDevice1GiPhone:
			[features appendString:@", 'phone'"]; 
			//[features appendString:@", 'camera'"]; 
			break;
		case UIDevice3GiPhone:
			[features appendString:@", 'phone'"]; 
			//[features appendString:@", 'camera'"]; 
			break;
		case UIDevice3GSiPhone:
			[features appendString:@", 'phone'"]; 
			//[features appendString:@", 'camera'"]; 
			break;
		case UIDevice4iPhone:
			[features appendString:@", 'phone'"]; 
			//[features appendString:@", 'camera'"]; 
			[features appendString:@", 'heading'"]; 
			[features appendString:@", 'rotation'"]; 
			break;
		case UIDevice1GiPad:
			[features appendString:@", 'heading'"]; 
			[features appendString:@", 'rotation'"]; 
			break;
		case UIDevice4GiPod:
			//[features appendString:@", 'camera'"]; 
			[features appendString:@", 'rotation'"]; 
			break;
		default:
			break;
	}
	
	// see if calendar support is available
	Class eventStore = NSClassFromString( @"EKEventStore" );
	if ( eventStore != nil )
	{
		[features appendString:@", 'calendar'"]; 
	}
	
	// setup the ad size
	CGSize size = m_webView.frame.size;
	
	// setup orientation
	UIDeviceOrientation orientation = m_currentDevice.orientation;
	NSInteger angle = [self angleFromOrientation:orientation];
	
	// setup the screen size
	UIDevice *device = [UIDevice currentDevice];
	CGSize screenSize = [device screenSizeForOrientation:orientation];	
	
	// get the key window
	UIApplication *app = [UIApplication sharedApplication];
	UIWindow *keyWindow = [app keyWindow];
	
	// setup the default position information (translated into window coordinates)
	CGRect defaultPosition = [self convertRect:self.frame
										toView:keyWindow];	
	
	// determine our network connectivity
	NSString *network = m_javascriptBridge.networkStatus;
	
	// build the initial properties
	NSString *properties = [NSString stringWithFormat:kInitialORMMAPropertiesFormat, @"default",
																					 network,
																					 size.width, size.height,
																					 self.maxSize.width, self.maxSize.height,
																					 screenSize.width, screenSize.height,
																					 defaultPosition.origin.x, defaultPosition.origin.y, defaultPosition.size.width, defaultPosition.size.height,
																					 angle,
																					 features];
	[self usingWebView:webView 
	 executeJavascript:@"window.ormmaview.fireChangeEvent( %@ );", properties];

	// make sure things are visible
	[self fireAdDidShow];
}


#pragma mark -
#pragma mark Delegate Helpers

- (void)fireAdWillShow
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(adWillShow:)] ) )
	{
		[self.ormmaDelegate adWillShow:self];
	}
}


- (void)fireAdDidShow
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(adDidShow:)] ) )
	{
		[self.ormmaDelegate adDidShow:self];
	}
}


- (void)fireAdWillHide
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(adWillHide:)] ) )
	{
		[self.ormmaDelegate adWillHide:self];
	}
}


- (void)fireAdDidHide
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(adDidHide:)] ) )
	{
		[self.ormmaDelegate adDidHide:self];
	}
}


- (void)fireAdWillClose
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(adWillClose:)] ) )
	{
		[self.ormmaDelegate adWillClose:self];
	}
}


- (void)fireAdDidClose
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(adDidClose:)] ) )
	{
		[self.ormmaDelegate adDidClose:self];
	}
}


- (void)fireAdWillResizeToSize:(CGSize)size
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(willResizeAd:toSize:)] ) )
	{
		[self.ormmaDelegate willResizeAd:self
								  toSize:size];
	}
}


- (void)fireAdDidResizeToSize:(CGSize)size
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(didResizeAd:toSize:)] ) )
	{
		[self.ormmaDelegate didResizeAd:self
								  toSize:size];
	}
}


- (void)fireAdWillExpandToFrame:(CGRect)frame
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(willExpandAd:toFrame:)] ) )
	{
		[self.ormmaDelegate willExpandAd:self
								 toFrame:frame];
	}
}


- (void)fireAdDidExpandToFrame:(CGRect)frame
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(didExpandAd:toFrame:)] ) )
	{
		[self.ormmaDelegate didExpandAd:self
								toFrame:frame];
	}
}


- (void)fireAppShouldSuspend
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(appShouldSuspendForAd:)] ) )
	{
		[self.ormmaDelegate appShouldSuspendForAd:self];
	}
}


- (void)fireAppShouldResume
{
	if ( ( self.ormmaDelegate != nil ) && 
		( [self.ormmaDelegate respondsToSelector:@selector(appShouldResumeFromAd:)] ) )
	{
		[self.ormmaDelegate appShouldResumeFromAd:self];
	}
}






#pragma mark -
#pragma mark Utility Methods

- (NSInteger)angleFromOrientation:(UIDeviceOrientation)orientation
{
	NSInteger orientationAngle = -1;
	switch ( orientation )
	{
		case UIDeviceOrientationPortrait:
			orientationAngle = 0;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			orientationAngle = 180;
			break;
		case UIDeviceOrientationLandscapeLeft:
			orientationAngle = 270;
			break;
		case UIDeviceOrientationLandscapeRight:
			orientationAngle = 90;
			break;
		default:
			orientationAngle = -1;
			break;
	}
	return orientationAngle;
}


- (void)callSelectorOnDelegate:(SEL)selector
{
	if ( ( self.ormmaDelegate != nil ) && 
 		 ( [self.ormmaDelegate respondsToSelector:selector] ) )
	{
		[self.ormmaDelegate performSelector:selector 
								 withObject:self];
	}
}


+ (void)copyFile:(NSString *)file
		  ofType:(NSString *)type
	  fromBundle:(NSBundle *)bundle
		  toPath:(NSString *)path
{
	NSString *sourcePath = [bundle pathForResource:file
											ofType:type];
	NSAssert( ( sourcePath != nil ), @"Source for file copy does not exist (%@)", file );
	NSString *contents = [NSString stringWithContentsOfFile:sourcePath
												   encoding:NSUTF8StringEncoding
													  error:NULL];
	
	// make sure path exists
	
	NSString *finalPath = [NSString stringWithFormat:@"%@/%@.%@", path, 
																  file, 
																  type];
	NSLog( @"Final Path to JS: %@", finalPath );
	NSError *error;
	if ( ![contents writeToFile:finalPath
					 atomically:YES
					   encoding:NSUTF8StringEncoding
						  error:&error] )
	{
		NSLog( @"Unable to write file '%@', to '%@'. Error is: %@", sourcePath, finalPath, error );
	}
}



#pragma mark -
#pragma mark Launch App Store

-(void)verifyAppStoreLaunchWithURL:(NSURL*)url 
{
	self.launchURL = url;
	
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Launch AppStore" 
													message:@"Application will exit.\nDo you wish to continue?"
												   delegate:self 
										  cancelButtonTitle:@"Cancel" 
										  otherButtonTitles: @"Continue", nil];
	[alert show];	
	[alert release];
}


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if ( buttonIndex != alertView.cancelButtonIndex )
	{
		[[UIApplication sharedApplication] openURL:self.launchURL];
	}
	
	self.launchURL = nil;
}







- (void)logFrame:(CGRect)f
			text:(NSString *)text
{
	NSLog( @"%@ :: ( %f, %f ) and ( %f x %f )", text,
												f.origin.x,
												f.origin.y,
												f.size.width,
												f.size.height );
}

@end