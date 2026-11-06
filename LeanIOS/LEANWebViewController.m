//
//  LEANWebViewController.m
//  LeanIOS
//
//  Created by Weiyin He on 2/10/14.
// Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import <WebKit/WebKit.h>
#import <MessageUI/MessageUI.h>
#import <CoreLocation/CoreLocation.h>
#import <AVFoundation/AVFoundation.h>

#import "LEANWebViewController.h"
#import "LEANWindowOverrideHandler.h"
#import "LEANAppDelegate.h"
#import "LEANUtilities.h"
#import "LEANHeaders.h"
#import "GNCustomHeaders.h"
#import "LEANMenuViewController.h"
#import "LEANNavigationController.h"
#import "LEANRootViewController.h"
#import "LEANJsCustomCodeExecutor.h"
#import "NSURL+LEANUtilities.h"
#import "LEANUrlInspector.h"
#import "LEANInstallation.h"
#import "LEANLaunchScreenManager.h"
#import "LEANKeyboardManager.h"
#import "LEANTabManager.h"
#import "LEANToolbarManager.h"
#import "LEANWebViewPool.h"
#import "LEANDocumentSharer.h"
#import "LEANLoadingSpinnerManager.h"
#import "Reachability.h"
#import "LEANActionManager.h"
#import "LEANPDFManager.h"
#import "LEANRegexRulesManager.h"
#import "MedianEventsManager.h"
#import "LEANWebViewIntercept.h"
#import "LEANWindowsManager.h"
#import "GNFileWriterSharer.h"
#import "GNConfigPreferences.h"
#import "GNBackgroundAudio.h"
#import "GonativeIO-Swift.h"
#import <AppTrackingTransparency/ATTrackingManager.h>
#import "GNLogManager.h"
#import "LEANNotifications.h"
#import "LEANUserAgentManager.h"
@import MedianCoreKMP;

#define OFFLINE_URL @"http://offline/"
#define LOCAL_FILE_URL @"http://localFile/"

// Shorthand for the median-core config singleton.
static MCKMPMutableConfigState* medianConfig(void) {
    return MCKMPMutableConfig.shared.instance;
}

@interface LEANWebViewController () <UISearchBarDelegate, UIActionSheetDelegate, UIScrollViewDelegate, UITabBarDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, MFMailComposeViewControllerDelegate, CLLocationManagerDelegate, MCKMPIOSAppHost, MCKMPCommandResponder, MCKMPWebViewBridgeGate>

@property WKWebView *wkWebview;

@property IBOutlet UIBarButtonItem* backButton;
@property IBOutlet UIBarButtonItem* forwardButton;
@property IBOutlet UINavigationItem* nav;
@property IBOutlet UIBarButtonItem* navButton;
@property IBOutlet UITabBar *tabBar;
@property IBOutlet UIToolbar *toolbar;
@property IBOutlet NSLayoutConstraint *tabBarBottomConstraint;
@property IBOutlet NSLayoutConstraint *toolbarBottomConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *pluginViewTopWebviewBottomConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *toolbarTopWebviewBottomConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *toolbarHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *tabbarTopWebviewBottomConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *tabbarHeightConstraint;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *webviewLeftSafeAreaLeft;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *webviewRightSafeAreaRight;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *toolbarLeftSafeAreaLeft;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *toolbarRightSafeAreaRight;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *tabbarLeftSafeAreaLeft;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *tabbarRightSafeAreaRight;
@property IBOutlet UIView *webviewContainer;
@property NSArray *defaultToolbarItems;
@property UIBarButtonItem *customActionButton;
@property NSArray *customActions;

@property UIView *statusBarBackground;
@property UIVisualEffectView *blurEffectView;
@property UIBarButtonItem *shareButton;
@property UIRefreshControl *pullRefreshControl;

@property BOOL keyboardVisible;
@property CGRect keyboardRect; // in window coordinates

@property NSURLRequest *currentRequest;
@property NSInteger urlLevel; // -1 for unknown
@property BOOL isWindowOpen;
@property NSTimer *timer;
@property BOOL startedLoading; // for transitions, keeps track of whether document.readystate has switched to "loading"
@property BOOL didLoadPage; // keep track of whether any page has loaded. If network reconnects, then will attempt reload if there is no page loaded
@property BOOL isPoolWebview;
@property UIView *defaultTitleView;
@property UIView *navigationTitleImageView;
@property CGFloat hideWebviewAlpha;
@property BOOL statusBarOverlay;
@property CGFloat savedScreenBrightness;
@property BOOL restoreBrightnessOnNavigation;
@property BOOL hasAppliedNav2; // nav2 (A1): this controller has rendered a resolved state
@property MCKMPTopNavComponent *lastAppliedTopNav; // nav2 (A1): top bar this controller last rendered

@property NSString *postLoadJavascript;
@property NSString *postLoadJavascriptForRefresh;

// Auto show/hide top navbar
@property CGFloat previousScrollY;
@property BOOL isShowingTopNavBar;
@property NSTimeInterval nextScrollTime;

@property CGFloat lastNavBarBottomY;

// Used to prevent race conditions when showing and hiding the tab bar and toolbar
@property (nonatomic, strong) NSMapTable<UIView *, NSNumber *> *barVisibility;

@property (nonatomic, copy) void (^locationPermissionBlock)(void);

@property BOOL visitedLoginOrSignup;

@property MedianEventsManager *eventsManager;
@property LEANActionManager *actionManager;
@property LEANToolbarManager *toolbarManager;
@property LEANRegexRulesManager *regexRulesManager;
@property LEANKeyboardManager *keyboardManager;
@property CLLocationManager *locationManager;
@property GNFileWriterSharer *fileWriterSharer;
@property NSString *connectivityCallback;
@property NSString *keyboardListenerCallback;
@property GNBackgroundAudio *backgroundAudio;
@property GNConfigPreferences *configPreferences;
@property LEANDocumentSharer *documentSharer;
@property GNLogManager *logManager;
@property GNCustomHeaders *customHeadersManager;
@property LEANWindowsManager *windowsManager;
@property LEANPDFManager *pdfManager;
@property LEANLoadingSpinnerManager *loadingSpinnerManager;
@property WebViewViewportManager *viewportManager;

@property NSNumber* statusBarStyle; // set via native bridge, only works if no navigation bar
@property IBOutlet NSLayoutConstraint *topGuideConstraint; // modify constant to place content under status bar

@property IBOutlet UIView *pluginView;
@property NSString *JSBridgeScript;
@property BOOL isFullscreen;

// median-core JS bridge (registers itself on JSBridge + medianBridge handler names)
@property MCKMPWebViewBridge *medianBridge;
@property MCKMPMessageRouter *messageRouter;

@end

@implementation LEANWebViewController

static CGRect sharePopOverRect; // last touch coordinates in CGRect
static NSInteger _currentWindows = 0;
static NSNumber *_windowOpenHideNavbar = nil; // runtime override of navigation.iosWindowOpenHideNavbar

+ (NSInteger)currentWindows {
  return _currentWindows;
}

+ (BOOL)windowOpenHideNavbar {
    if (!_windowOpenHideNavbar) {
        _windowOpenHideNavbar = @(medianConfig().configRoot.navigation.iosWindowOpenHideNavbar);
    }
    return _windowOpenHideNavbar.boolValue;
}

+ (void)setWindowOpenHideNavbar:(BOOL)hide {
    _windowOpenHideNavbar = @(hide);
}

+ (void)setCurrentWindows:(NSInteger) currentWindows {
    _currentWindows = currentWindows;
    [WindowsController windowCountChanged];
}

- (void)updateWindowsController {
    [WindowsController windowCountChanged];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self becomeFirstResponder];
    LEANWebViewController.currentWindows += 1;
    self.checkLoginSignup = YES;

    MCKMPMutableConfigState *config = medianConfig();

    self.barVisibility = [NSMapTable weakToStrongObjectsMapTable];

    // enable touch listener only for iPads
    if(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad){
        UITapGestureRecognizer *coordinateListener =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:nil];
        coordinateListener.delegate = (id)self;
        // Set required taps and number of touches
        [coordinateListener setNumberOfTapsRequired:1];
        [coordinateListener setNumberOfTouchesRequired:1];
        [[self view] addGestureRecognizer:coordinateListener];
    }

    self.hideWebviewAlpha = config.configRoot.styling.hideWebviewAlpha;
    self.statusBarOverlay = config.configRoot.styling.iosEnableOverlayInStatusBar;
    self.savedScreenBrightness = -1;
    self.restoreBrightnessOnNavigation = NO;
    self.previousScrollY = 0;

    self.tabManager = [[LEANTabManager alloc] initWithTabBar:self.tabBar heightConstraint:self.tabbarHeightConstraint wvc:self];
    self.toolbarManager = [[LEANToolbarManager alloc] initWithToolbar:self.toolbar heightConstraint:self.toolbarHeightConstraint wvc:self];
    self.messageRouter = [MCKMPIOSCommandFactory.shared registerAllRouter:[[MCKMPMessageRouter alloc] init]];
    self.fileWriterSharer = [[GNFileWriterSharer alloc] init];
    self.fileWriterSharer.wvc = self;
    self.customHeadersManager = [[GNCustomHeaders alloc] init];

    // Launch screen overlay
    [[LEANLaunchScreenManager sharedManager] showWithParentViewController:self];

    // set title to application title
    if (config.navigationTitles.count == 0) {
        self.navigationItem.title = config.configRoot.general.appName;
    }

    self.visitedLoginOrSignup = NO;
    
    if (self.initialWebview) {
        [self switchToWebView:self.initialWebview showImmediately:YES];
        self.initialWebview = nil;
        
        // nav title image
        if (self.wkWebview.URL) {
            [self checkNavigationTitleImageForUrl:self.wkWebview.URL];
        }
        
    } else {
        if ([LEANUserAgentManager sharedManager].userAgentReady) {
            [self initializeWebview];
        } else {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:kGoNativeAppConfigNotificationUserAgentReady object:nil];
        }
    }
    
    // hide ad banner view initially
    self.pluginViewTopWebviewBottomConstraint.active = NO;
    
    // Move bottom tab bar down when glass design is enabled
    if ([LEANUtilities isGlassDesignEnabled]) {
        self.tabBarBottomConstraint.active = NO;
        self.tabBarBottomConstraint = [self.view.bottomAnchor constraintEqualToAnchor:self.tabBar.bottomAnchor];
        self.tabBarBottomConstraint.active = YES;
    }
    
    // hidden nav bar
    if (!config.configRoot.styling.showNavigationBar && [self isRootWebView]) {
        UIToolbar *bar = [[UIToolbar alloc] init];
        if ([config.configRoot.styling.iosTheme isEqualToString:@"dark"]) {
            bar.barStyle = UIBarStyleBlack;
        }
        self.statusBarBackground = bar;
        [self.view addSubview:self.statusBarBackground];
    }


    [self updateStatusBarBackgroundColor:[UIColor colorNamed:@"statusBarBackgroundColor"] enableBlurEffect:config.configRoot.styling.iosEnableBlurInStatusBar];

    [self updateNavigationBarItemsAnimated:NO];
    [self buildDefaultToobar];
    self.keyboardVisible = NO;
    self.keyboardRect = CGRectZero;
    [self adjustInsets];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:kLEANAppConfigNotificationProcessedTabNavigation object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:kLEANAppConfigNotificationProcessedNavigationTitles object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:kLEANAppConfigNotificationProcessedNavigationLevels object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:kLEANAppConfigNotificationNavigationInstanceChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:kReachabilityChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    
    // keyboard change notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
    
    // to help fix status bar issues when rotating in full-screen video
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged) name:UIDeviceOrientationDidChangeNotification object:nil];
    
    self.eventsManager = [[MedianEventsManager alloc] initWithWebViewController:self];
    self.actionManager = [[LEANActionManager alloc] initWithWebviewController:self];
    
    self.regexRulesManager = [[LEANRegexRulesManager alloc] initWithWvc:self];
    self.windowsManager = [[LEANWindowsManager alloc] initWithWvc:self];
    
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    
    self.backgroundAudio = [[GNBackgroundAudio alloc] init];
    self.configPreferences = [GNConfigPreferences sharedPreferences];
    self.documentSharer = [LEANDocumentSharer sharedSharer];
    self.keyboardManager = [LEANKeyboardManager shared];
    self.pdfManager = [LEANPDFManager shared];
    self.loadingSpinnerManager = [[LEANLoadingSpinnerManager alloc] initWithVc:self];
    self.viewportManager = [WebViewViewportManager shared];
    
    // we will always be loading a page at launch, hide webview here to fix a white flash for dark themed apps
    [self hideWebview];
    
    // enable full screen webview i.e turn off safe area constraints
    if(config.configRoot.general.iosFullScreenWebview){
        // webview
        [self.webviewLeftSafeAreaLeft setActive:NO];
        [self.webviewRightSafeAreaRight setActive:NO];
        // tab Bar
        [self.tabbarLeftSafeAreaLeft setActive:NO];
        [self.tabbarRightSafeAreaRight setActive:NO];
        // toolbar
        [self.toolbarLeftSafeAreaLeft setActive:NO];
        [self.toolbarRightSafeAreaRight setActive:NO];
    }
    
    // add nav button
    if (config.showNavigationMenu && [self isRootWebView]) {
        [self setSidebarEnabled:YES];
    }
    
    // set initial native theme
    NSString *mode = [[NSUserDefaults standardUserDefaults] objectForKey:@"darkMode"];
    [self setNativeTheme:mode ?: config.configRoot.styling.iosDarkMode];
    [self updateStatusBarStyle:config.configRoot.styling.iosStatusBarStyle];
    [self updateStatusBarOverlay:config.configRoot.styling.iosEnableOverlayInStatusBar];

    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge onViewDidLoadHost:self];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

// called when screen touched
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:touch.view];
    CGPoint pointOnScreen = [touch.view convertPoint:point toView:nil];
    sharePopOverRect = CGRectMake(pointOnScreen.x, pointOnScreen.y, 0, 0);
    return NO;
}

// set share dialog popover location in CGRect
- (void)setSharePopOverRect:(CGRect)rect
{
    sharePopOverRect = rect;
}

-(void)initializeWebview
{
    MCKMPMutableConfigState *appConfig = medianConfig();
    WKWebViewConfiguration *config = [[NSClassFromString(@"WKWebViewConfiguration") alloc] init];
    config.processPool = [LEANUtilities wkProcessPool];
    config.allowsInlineMediaPlayback = YES;

    WKWebView *wv = [[NSClassFromString(@"WKWebView") alloc] initWithFrame:self.wkWebview.frame configuration:config];
    [LEANUtilities configureWebView:wv];

    [self.keyboardManager setTargetWebview:wv];
    [self.keyboardManager showKeyboardAccessoryView:appConfig.configRoot.general.iosShowKeyboardAccessoryView];

    [self switchToWebView:wv showImmediately:NO];
    
#if DEBUG
    if (@available(iOS 16.4, *)) {
        if ([wv respondsToSelector:@selector(setInspectable:)]) {
            [(LEANHeaders *)wv setInspectable:YES];
        }
    }
#endif
    
    // load initial url
    self.urlLevel = -1;
    if (!self.initialUrl) {
        NSString *initialUrlPref = [self.configPreferences getInitialUrl];
        if (initialUrlPref && initialUrlPref.length > 0) {
            self.initialUrl = [NSURL URLWithString:initialUrlPref];
            [self.configPreferences setInitialUrl:initialUrlPref];
        }
    }
    NSURL *configInitialUrl = [NSURL URLWithString:appConfig.initialUrl];
    if (!self.initialUrl && configInitialUrl) {
        NSURLComponents *components = [[NSURLComponents alloc] initWithURL:configInitialUrl resolvingAgainstBaseURL:NO];
        NSMutableArray *newQueryItems = [NSMutableArray array];
        if (components.queryItems) {
            [newQueryItems addObjectsFromArray:components.queryItems];
        }

        NSArray *addedQueryItems = [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge getInitialUrlQueryItems];
        [newQueryItems addObjectsFromArray:addedQueryItems];

        components.queryItems = newQueryItems;
        if (newQueryItems.count > 0) {
            self.initialUrl = [components URL];
        } else {
            self.initialUrl = configInitialUrl;
        }
    }
    
    [self loadUrl:self.initialUrl];
    
    // nav title image
    [self checkNavigationTitleImageForUrl:self.initialUrl];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.wkWebview) {
        @try {
            [self.wkWebview removeObserver:self forKeyPath:@"URL"];
            [self.wkWebview removeObserver:self forKeyPath:@"canGoBack"];
            [self.wkWebview removeObserver:self forKeyPath:@"canGoForward"];
        }
        @catch (NSException * __unused exception) {
        }
    }
    LEANWebViewController.currentWindows -= 1;
}

- (void)didReceiveNotification:(NSNotification*)notification
{
    NSString *name = [notification name];
    if ([name isEqualToString:kGoNativeAppConfigNotificationUserAgentReady]) {
        [self initializeWebview];
    }
    else if ([name isEqualToString:kLEANAppConfigNotificationProcessedTabNavigation]) {
        [self checkNavigationForUrl:self.currentRequest.URL];
    }
    else if ([name isEqualToString:UIApplicationDidBecomeActiveNotification]) {
        [self retryFailedPage];
    }
    else if ([name isEqualToString:kReachabilityChangedNotification]) {
        [self retryFailedPage];
        if (self.connectivityCallback) {
            NSDictionary *status = [self getConnectivity];
            NSString *js = [LEANUtilities createJsForCallback:self.connectivityCallback data:status];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self runJavascript:js];
            });
        }
    }
    else if ([name isEqualToString:kLEANAppConfigNotificationProcessedNavigationTitles]) {
        NSURL *url = nil;
        if (self.wkWebview) url = self.wkWebview.URL;

        if (url) {
            NSString *newTitle = [LEANWebViewController titleForUrl:url];
            if (newTitle) {
                self.navigationItem.title = newTitle;
            } else {
                self.navigationItem.title = medianConfig().configRoot.general.appName;
            }
        }
    }
    else if ([name isEqualToString:kLEANAppConfigNotificationProcessedNavigationLevels]) {
        NSURL *url = nil;
        if (self.wkWebview) url = self.wkWebview.URL;

        if (url) {
            self.urlLevel = [LEANWebViewController urlLevelForUrl:url];
        }
    }
    else if ([name isEqualToString:kLEANAppConfigNotificationNavigationInstanceChanged]) {
        // nav2 (A1): since 2.4.1 the resolver is pure and this fires only when the JS
        // override layer changes. Re-render for our own current URL only; hidden
        // controllers re-apply in viewWillAppear.
        if (self.viewIfLoaded.window && self.wkWebview.URL) {
            [self applyNav2ForUrl:self.wkWebview.URL];
        }
    }
    else if ([name isEqualToString:UIContentSizeCategoryDidChangeNotification]) {
        NSString *contentSizeCategory = notification.userInfo[UIContentSizeCategoryNewValueKey];
        [LEANUtilities applyFontScalingForContentSize:contentSizeCategory toWebView:self.wkWebview asUserScript:NO];
    }
}

- (void)keyboardShown:(NSNotification*)notification
{
    NSDictionary* info = [notification userInfo];
    CGRect kbRect = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    self.keyboardRect = kbRect;
    self.keyboardVisible = YES;
    [self adjustInsets];

    [self runKeyboardInfoWithCallback:self.keyboardListenerCallback];
}

- (void)keyboardHidden:(NSNotification*)notification
{
    self.keyboardVisible = NO;
    self.keyboardRect = CGRectZero;
    [self adjustInsets];
    
    // work around a bug starting in iOS 12 where the scroll doesn't readjust when the keyboard is hidden
    UIEdgeInsets inset = self.wkWebview.scrollView.contentInset;
    [self.wkWebview.scrollView setContentInset:UIEdgeInsetsMake(inset.top + 0.0001, inset.left, inset.bottom, inset.right)];
    [self.wkWebview.scrollView setContentInset:inset];

    [self runKeyboardInfoWithCallback:self.keyboardListenerCallback];
}

- (void)retryFailedPage
{
    // return if we are not the top view controller
    if (![self isViewLoaded] || !self.view.window) return;
    
    // if there is a page loaded, user can just retry navigation
    if (self.didLoadPage) return;
    
    // return if currently loading a page
    if (self.wkWebview && self.wkWebview.isLoading) return;
    
    NetworkStatus status = [((LEANAppDelegate*)[UIApplication sharedApplication].delegate).internetReachability currentReachabilityStatus];
    
    if (status != NotReachable && self.currentRequest) {
        NSLog(@"Networking reconnect. Retrying previous failed request.");
        [self loadRequest:self.currentRequest];
    }
}

- (void)addPullToRefresh
{
    if (!self.pullRefreshControl) {
        self.pullRefreshControl = [[UIRefreshControl alloc] init];
        [self.pullRefreshControl addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
        self.pullRefreshControl.tintColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    }
    
    [self.wkWebview.scrollView addSubview:self.pullRefreshControl];
    
    self.wkWebview.scrollView.bounces = YES;
}

- (void)removePullRefresh
{
    self.wkWebview.scrollView.bounces = NO;
    [self.pullRefreshControl removeFromSuperview];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (medianConfig().configRoot.navigation.iosPullToRefresh) {
        [self addPullToRefresh];
    }
    
    [self adjustInsets];
    
    NSURL *url = self.wkWebview.URL;
    if (url) {
        [self checkNavigationTitleImageForUrl:url];
        [self checkNavigationForUrl:url];
    }
    
    [self addScriptMessageHandlersInWebView:self.wkWebview];

    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge onViewWillAppearHost:self];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self.pullRefreshControl removeFromSuperview];
    
    if (self.isMovingFromParentViewController) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserFinishedLoading object:self];
    }
    [super viewWillDisappear:animated];

    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge onViewWillDisappearHost:self];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [self.tabManager traitCollectionDidChange:previousTraitCollection];
    [self.actionManager traitCollectionDidChange:previousTraitCollection];
}

- (void) buildDefaultToobar
{
    NSMutableArray *array = [self.toolbarItems mutableCopy];

    if (medianConfig().configRoot.showShareButton.boolValue) {
        UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(buttonPressed:)];
        shareButton.tag = 3;
        [array addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
        [array addObject:shareButton];
    }
    self.defaultToolbarItems = array;
    [self setToolbarItems:array animated:NO];
}

-(void)setSidebarEnabled:(BOOL)enabled
{
    if (![self isRootWebView]) return;

    if (!medianConfig().showNavigationMenu && !medianConfig().isNativeNavigationV2) return;
    
    LEANNavigationController *navController = (LEANNavigationController*)self.navigationController;
    [navController setSidebarEnabled:enabled];
    
    if (enabled) {
        [self showSidebarNavButton];
    } else {
        self.navButton = nil;
        [navController.frostedViewController hideMenuViewController];
    }
}

- (void)checkPreNavigationForUrl:(NSURL*)url
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkNavigationTitleImageForUrl:url];
        [self.tabManager autoSelectTabForUrl:url];
    });
}

// Native Navigation V2: resolve the per-URL instance and feed the existing V1 bar machinery
- (void)applyNav2ForUrl:(NSURL*)url
{
    if (!url) return;
    MCKMPResolvedNavigation *resolved = [medianConfig() resolveNavigationForUrlUrl:url.absoluteString ?: @""];
    if (!resolved) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.hasAppliedNav2 = YES; // A1: per-controller tracking
        self.lastAppliedTopNav = resolved.topNavigationBar;
        MCKMPTopNavComponent *topNav = resolved.topNavigationBar;
        MCKMPSidebarComponent *sidebar = resolved.sidebarNavigationBar;

        // sidebar: items into the existing menu controller. The hamburger follows the sidebar
        // alone, as in V1, App Studio and Android: allowLeftMenu is the top bar's left slot,
        // and gating the sidebar on it hid the sidebar whenever that slot was off.
        // The menu is shared by the whole stack and belongs to the root screen.
        if ([self isRootWebView]) {
            BOOL sidebarActive = sidebar && sidebar.active && sidebar.items.count > 0;
            [(LEANMenuViewController*)self.frostedViewController.menuViewController setNav2MenuItems:sidebarActive ? sidebar.items : @[]];
            [self setSidebarEnabled:sidebarActive];
        }

        // top bar: buttons via the action manager, visibility + title via dynamicTitle
        [self.actionManager loadNav2TopNav:topNav];
        [self applyNav2TopBar:topNav forUrl:url];

        // bottom tabs
        if (!self.tabManager.javascriptTabs) {
            [self.tabManager loadNav2Component:resolved.bottomTabBar forUrl:url];
        }

        // contextual toolbar
        [self.toolbarManager didLoadNav2Url:url component:resolved.contextualNavToolbar];
        [self.toolbar layoutSubviews];
    });
}

// nav2 top bar: `active` is the visibility switch; dynamicTitle carries V1 navigationTitles semantics
- (void)applyNav2TopBar:(MCKMPTopNavComponent*)topNav forUrl:(NSURL*)url
{
    BOOL hideForWindowOpen = self.isWindowOpen && LEANWebViewController.windowOpenHideNavbar;
    if (!topNav || !topNav.active || hideForWindowOpen) {
        self.isShowingTopNavBar = NO;
        self.defaultTitleView = nil;
        self.navigationItem.titleView = nil;
        [self.navigationController setNavigationBarHidden:YES animated:YES];
        return;
    }

    NSString *title = nil;
    BOOL showImage = NO;
    MCKMPDynamicTitle *dynamicTitle = topNav.dynamicTitle;
    if (dynamicTitle) {
        NSString *urlString = url.absoluteString ?: @"";
        BOOL matched = NO;
        // per-URL rules first (V1 NavigationTitleRule semantics: first regex match wins)
        for (MCKMPNavigationTitleRule *rule in dynamicTitle.titles) {
            @try {
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", rule.regex];
                if ([predicate evaluateWithObject:urlString]) {
                    showImage = rule.showImage;
                    title = (rule.customTitle && rule.title.length > 0) ? rule.title : self.wkWebview.title;
                    matched = YES;
                    break;
                }
            }
            @catch (NSException *exception) {
                NSLog(@"Error in nav2 title regex: %@", exception);
            }
        }
        if (!matched) {
            showImage = dynamicTitle.showImage;
            if (dynamicTitle.customTitle && dynamicTitle.title.length > 0) {
                title = dynamicTitle.title;
            }
        }
    }
    if (!showImage && title.length == 0) {
        title = medianConfig().configRoot.general.appName;
    }

    [self renderNavigationTitle:title showImage:showImage];

    // an active nav2 top bar stays visible even without a title
    self.isShowingTopNavBar = YES;
    [self.navigationController setNavigationBarHidden:NO animated:YES];
}

- (void)checkNavigationForUrl:(NSURL*) url;
{
    if (medianConfig().isNativeNavigationV2) {
        [self applyNav2ForUrl:url];
        return;
    }

    if (!self.tabManager.javascriptTabs) {
        if (medianConfig().configRoot.navigation.tabNavigation.tabMenus.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideTabBarAnimated:YES];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tabManager didLoadUrl:url];
                // toolbar may need to adjust its background to fill in behind home indicator
                [self.toolbar layoutSubviews];
            });
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.toolbarManager didLoadUrl:url];
        // toolbar may need to adjust its background to fill in behind home indicator
        [self.toolbar layoutSubviews];
    });
}

- (void)checkNavigationTitleImageForUrl:(NSURL*)url
{
    // check if navbar titles has regex match
    MCKMPMutableConfigState *appConfig = medianConfig();

    if (appConfig.isNativeNavigationV2) {
        MCKMPResolvedNavigation *resolved = [appConfig resolveNavigationForUrlUrl:url.absoluteString ?: @""];
        // A1: top-bar-only refreshes (pre-navigation target URL, title KVO on the old
        // URL) can race the full apply. Once a top bar has been rendered, only
        // refreshes resolving to that same top bar go through here; top bar switches
        // render via applyNav2ForUrl: on the actual navigation event.
        MCKMPTopNavComponent *topNav = resolved.topNavigationBar;
        BOOL sameTopNav = !self.hasAppliedNav2 ||
            topNav == self.lastAppliedTopNav || [topNav isEqual:self.lastAppliedTopNav];
        if (resolved && sameTopNav) {
            [self applyNav2TopBar:topNav forUrl:url];
        }
        return;
    }

    NSString *title;
    BOOL showImageView = NO;

    // Handle windowOpenHideNavbar
    if (!self.isWindowOpen || !LEANWebViewController.windowOpenHideNavbar) {
        BOOL hasRegexMatch = NO;

        // Check regex match (first matching rule wins)
        MCKMPNavigationTitleRule *rule = [appConfig titleRuleForUrlUrl:url.absoluteString ?: @""];
        if (rule) {
            showImageView = rule.showImage;
            title = (rule.customTitle && rule.title.length > 0) ? rule.title : self.wkWebview.title;
            hasRegexMatch = YES;
        }

        // If no regex match and display mode is always
        if (!hasRegexMatch && appConfig.configRoot.styling.showNavigationBar) {
            showImageView = appConfig.configRoot.styling.navigationTitleImage;
            title = appConfig.configRoot.general.appName;
        }
    }

    [self renderNavigationTitle:title showImage:showImageView];
}

// shared title/image rendering for the V1 and nav2 paths; sets isShowingTopNavBar
- (void)renderNavigationTitle:(NSString*)title showImage:(BOOL)showImageView
{
    self.navigationItem.title = nil;

    // show logo in navigation bar
    if (showImageView) {
        // create the view if necesary
        if (!self.navigationTitleImageView) {
            // production uses the bundled NavBarImage asset (preview override is a builder concern)
            UIImage *im = [UIImage imageNamed:@"NavBarImage"];

            if (im) {
                CGRect bounds = CGRectMake(0, 0, 30 * im.size.width / im.size.height, 30);
                UIView *backView = [[UIView alloc] initWithFrame:bounds];
                UIImageView *iv = [[UIImageView alloc] initWithImage:im];
                iv.bounds = bounds;
                [backView addSubview:iv];
                iv.center = backView.center;
                self.navigationTitleImageView = backView;
            }
        }
        
        // set the view
        self.defaultTitleView = self.navigationTitleImageView;
        self.navigationItem.titleView = self.navigationTitleImageView;
        self.isShowingTopNavBar = YES;
    } else {
        self.defaultTitleView = nil;
        self.navigationItem.titleView = nil;
        self.isShowingTopNavBar = title != nil;
        
        if ([title isKindOfClass:[NSString class]] && title.length > 0) {
            if (@available(iOS 26.0, *)) {
                if ([LEANUtilities isGlassDesignEnabled]) {
                    LEANLiquidTitleView *titleView = [LEANLiquidTitleView new];
                    titleView.text = title;
                    self.navigationItem.titleView = titleView;
                } else {
                    self.navigationItem.title = title;
                }
            } else {
                self.navigationItem.title = title;
            }
        }
    }
    
    [self.navigationController setNavigationBarHidden:!self.isShowingTopNavBar animated:YES];
}

- (void)hideTabBarAnimated:(BOOL)animated
{
    self.tabbarTopWebviewBottomConstraint.active = NO;
    [self hideBottomBar:self.tabBar constraint:self.tabBarBottomConstraint animated:animated];
}

- (void)hideToolbarAnimated:(BOOL)animated
{
    self.toolbarTopWebviewBottomConstraint.active = NO;
    [self hideBottomBar:self.toolbar constraint:self.toolbarBottomConstraint animated:animated];
}

- (void)showTabBarAnimated:(BOOL)animated
{
    self.tabbarTopWebviewBottomConstraint.active = YES;
    [self showBottomBar:self.tabBar constraint:self.tabBarBottomConstraint animated:animated];
}

- (void)showToolbarAnimated:(BOOL)animated
{
    self.toolbarTopWebviewBottomConstraint.active = YES;
    [self showBottomBar:self.toolbar constraint:self.toolbarBottomConstraint animated:animated];
}

- (void)showBottomBar:(UIView*)bar constraint:(NSLayoutConstraint*)constraint animated:(BOOL)animated
{
    if ([self.barVisibility objectForKey:bar].boolValue) {
        return;
    }
    
    [self.view layoutIfNeeded];
    bar.hidden = NO;
    constraint.constant = 0;
    [self.barVisibility setObject:@YES forKey:bar];
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^(void){
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished){
            if ([self.barVisibility objectForKey:bar].boolValue) {
                [self adjustInsets];
            }
        }];
    } else {
        [self.view layoutIfNeeded];
        [self adjustInsets];
    }
}

- (void)hideBottomBar:(UIView*)bar constraint:(NSLayoutConstraint*)constraint animated:(BOOL)animated
{
    [self.view layoutIfNeeded];
    CGFloat barHeight = MIN(bar.bounds.size.width, bar.bounds.size.height);
    constraint.constant = -barHeight;

    NSNumber *visibility = [self.barVisibility objectForKey:bar];
    if (visibility != nil && !visibility.boolValue) {
        [self.view layoutIfNeeded];
        return;
    }
    
    [self.barVisibility setObject:@NO forKey:bar];
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^(void){
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished){
            if (![self.barVisibility objectForKey:bar].boolValue) {
                bar.hidden = YES;
                [self adjustInsets];
            }
        }];
    } else {
        [self.view layoutIfNeeded];
        bar.hidden = YES;
        [self adjustInsets];
    }
}

- (CGFloat)getNavigationBarBottomY {
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    CGRect navigationBarFrame = navigationBar.frame;

    if (navigationBar.superview) {
        navigationBarFrame = [navigationBar.superview convertRect:navigationBarFrame toView:self.view];
    }

    CGFloat y = CGRectGetMaxY(navigationBarFrame);
    
    // y is 0 when the navbar is hidden, so save the last value
    if (y > 0) {
        self.lastNavBarBottomY = y;
        return y;
    }
    
    return self.lastNavBarBottomY;
}

- (void)applyStatusBarOverlay {
    CGFloat statusBarHeight = [UIApplication sharedApplication].currentStatusBarFrame.size.height;
        
    // Top guide is equal to super view (below top navbar)
    if ([LEANUtilities isGlassDesignEnabled]) {
        self.topGuideConstraint.constant = self.statusBarOverlay ? 0 : statusBarHeight;
        
        if (self.isShowingTopNavBar) {
            CGFloat topInset = MAX(0, [self getNavigationBarBottomY] - self.topGuideConstraint.constant);
            self.wkWebview.scrollView.contentInset = UIEdgeInsetsMake(topInset, 0, 0, 0);
            if (@available(iOS 26.0, *)) {
                self.wkWebview.obscuredContentInsets = UIEdgeInsetsMake(topInset, 0, 0, 0);
            }
        }
    }
    else {
        CGFloat topInset = statusBarHeight;
        if (self.isShowingTopNavBar) {
            topInset = [self getNavigationBarBottomY];
        }
        self.topGuideConstraint.constant = self.statusBarOverlay ? 0 : topInset;
    }
}

- (void)adjustInsets
{
    // This function used to adjust the content inset of the webview's scrollview, but we
    // have moved away from that strategy. Now we just let autolayout constraints resize
    // the webview frame, and set masksToBounds=false
}

- (IBAction) buttonPressed:(id)sender
{
    switch ((long)[((UIBarButtonItem*) sender) tag]) {
        case 1:
            // back
            if (self.wkWebview.canGoBack)
                [self.wkWebview goBack];
            break;
            
        case 2:
            // forward
            if (self.wkWebview.canGoForward)
                [self.wkWebview goForward];
            break;
            
        case 3:
            //action
            [self sharePageWithUrl:nil text:nil sender:sender];
            break;
            
        case 4:
            //search
            NSLog(@"search");
            break;
            
        case 5:
            //refresh
            if (self.wkWebview.URL && ![[self.wkWebview.URL absoluteString] isEqualToString:@""]) {
                [self.wkWebview reload];
            }
            else {
                [self loadRequest:self.currentRequest];
            }
            break;
        
        default:
            break;
    }
    
}

- (void) searchPressed:(id)sender
{
    UISearchBar *searchBar = [[UISearchBar alloc] init];
    searchBar.showsCancelButton = NO;
    searchBar.delegate = self;
    
    self.navigationItem.titleView = searchBar;
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"button-cancel", @"Button: Cancel") style:UIBarButtonItemStylePlain target:self action:@selector(searchCanceled)];
    
    [self.navigationItem setHidesBackButton:YES animated:YES];
    [self.navigationItem setLeftBarButtonItems:nil animated:YES];
    [self.navigationItem setRightBarButtonItems:@[cancelButton] animated:YES];
    [searchBar becomeFirstResponder];
}

- (void) sharePressed:(UIBarButtonItem*)sender
{
    [self.documentSharer shareRequest:self.currentRequest fromButton:sender];
}

- (void) updateNavigationBarItemsAnimated:(BOOL)animated {
    BOOL backButtonShown = self.urlLevel > 1 || self.isWindowOpen;
    BOOL allowLeftAction = !backButtonShown && self.navButton == nil;
    LEANActionButtons *actions = [self.actionManager configureNavBarButtonsAllowingLeftAction:allowLeftAction];
    
    if (self.navButton) {
        [self.navigationItem setLeftBarButtonItems:@[self.navButton] animated:animated];
    } else {
        [self.navigationItem setLeftBarButtonItems:actions.leftItems animated:animated];
    }
    
    [self.navigationItem setRightBarButtonItems:actions.rightItems animated:animated];
    [self.navigationItem setHidesBackButton:NO animated:animated];
}

- (void) sharePage:(id)sender
{
    [self sharePageWithUrl:nil text:nil sender:sender];
}

- (void) sharePageWithUrl:(NSString*)url text:(NSString*)text sender:(id)sender;
{
    NSURL *shareUrl = self.currentRequest.URL;
    if (url) {
        shareUrl = [NSURL URLWithString:url relativeToURL:self.currentRequest.URL];
    }
    
    NSString *shareData = shareUrl.absoluteString;
    if (text) {
        shareData = [NSString stringWithFormat:@"%@\n%@", text, shareUrl];
    }

    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[shareData] applicationActivities:nil];
    
    // For iPads starting in iOS 8, we need to specify where the pop over should occur from.
    if ( [avc respondsToSelector:@selector(popoverPresentationController)] ) {
        if ([sender isKindOfClass:[UIBarButtonItem class]]) {
            avc.popoverPresentationController.barButtonItem = sender;
        } else if ([sender isKindOfClass:[UIView class]]) {
            avc.popoverPresentationController.sourceView = sender;
        } else {
            if(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad){
                avc.popoverPresentationController.sourceRect = sharePopOverRect;
            }
            avc.popoverPresentationController.sourceView = self.view;
        }
    }
    
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)refreshPressed:(id)sender
{
    [self refreshPage];
}

-(void)pullToRefresh:(UIRefreshControl*) refresh
{
    [self refreshPage];
    [refresh endRefreshing];
}

- (void)refreshPage
{
    NSString *currentUrl = self.wkWebview.URL.absoluteString;
    if ([currentUrl isEqualToString:OFFLINE_URL]) {
        if ([self.wkWebview canGoBack]) {
            [self.wkWebview goBack];
        } else {
            [self loadUrl:self.initialUrl];
        }
    } else {
        [self.wkWebview reload];
    }
}

- (void) logout
{
    [self.wkWebview stopLoading];
    // stop webview pools
    [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserStartedLoading object:self];
    [[LEANWebViewPool sharedPool] flushAll];

    // clear cookies
    NSHTTPCookie *cookie;
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (cookie in [storage cookies]) {
        [storage deleteCookie:cookie];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];

    // load initial page in bottom webview
    [self.navigationController popToRootViewControllerAnimated:NO];
    [self.navigationController.viewControllers[0] loadUrl:[NSURL URLWithString:medianConfig().initialUrl]];

    [(LEANMenuViewController*)self.frostedViewController.menuViewController updateMenuWithStatus:@"default"];
}

- (IBAction) showMenu
{
    [self.frostedViewController presentMenuViewController];
}

- (BOOL)canGoBack
{
    if (self.wkWebview) {
        return [self.wkWebview canGoBack];
    } else {
        return NO;
    }
}

- (void)goBack
{
    if (self.wkWebview && [self.wkWebview canGoBack]) {
        [self.wkWebview goBack];
    }
}

- (BOOL)canGoForward
{
    if (self.wkWebview) {
        return [self.wkWebview canGoForward];
    } else {
        return NO;
    }
}

- (void)goForward
{
    if (self.wkWebview && [self.wkWebview canGoForward]) {
        [self.wkWebview goForward];
    }
}

- (void)refresh
{
    if (self.wkWebview) {
        [self.wkWebview reload];
    }
}

- (void)triggerEvent:(NSString *)eventName data:(NSDictionary *)data {
    [self.eventsManager triggerEvent:eventName data:data];
}

- (void)handleJsNavigationUrl:(NSString *)url {
    if (!url || url.length == 0) {
        return;
    } else if ([url hasPrefix:@"javascript:"]) {
        [self runJavascript:[url substringFromIndex: [@"javascript:" length]]];
    } else if ([self.eventsManager isSubscribedForEvent:@"_median_url_changed"]) {
        [self.eventsManager triggerEvent:@"_median_url_changed" data:@{ @"url": url }];
    } else {
        [self loadUrlAfterFilter:[LEANUtilities urlWithString:url]];
    }
}

- (void) loadUrlString:(NSString*)url
{
    if ([url length] == 0) {
        return;
    }
    
    if ([url hasPrefix:@"javascript:"]) {
        NSString *js = [url substringFromIndex: [@"javascript:" length]];
        [self runJavascript:js];
    } else {
        [self loadUrlAfterFilter:[NSURL URLWithString:url]];
    }
}

- (void) loadUrlAfterFilter:(NSURL *)url
{
    if([url.scheme isEqualToString:@"gonative"] || [url.scheme isEqualToString:@"median"]){
        [self handleJSBridgeFunctions:url];
    } else {
        [self loadUrl:url];
    }
    
}

- (void) loadUrl:(NSURL *)url
{
    // in case this is called before the user agent stuff has finished
    if (![LEANUserAgentManager sharedManager].userAgentReady) {
        self.initialUrl = url;
        return;
    }
    
    // local file url
    if ([url.scheme isEqualToString:@"file"]) {
        NSArray *components = [url.path componentsSeparatedByString:@"."];
        NSString *filePath;
        if (components.count == 2 && [components[components.count - 1] isEqualToString:@"html"]) {
            filePath = components[0];
        }
        NSURL *localUrl = [[NSBundle mainBundle] URLForResource:filePath withExtension:@"html"];
        if (localUrl) {
            NSString *html = [NSString stringWithContentsOfURL:localUrl encoding:NSUTF8StringEncoding error:nil];
            [self.wkWebview loadHTMLString:html baseURL:[NSURL URLWithString:LOCAL_FILE_URL]];
        } else {
            [self showOfflinePage];
        }
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSNumber *timeout = medianConfig().configRoot.navigation.iosConnectionOfflineTime;
    if (timeout) {
        request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:[timeout doubleValue]];
    }
    [self loadRequest:request];
}


- (void) loadRequest:(NSURLRequest*) request
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserStartedLoading object:self];
    [self.wkWebview loadRequest:request];
    self.postLoadJavascript = nil;
    self.postLoadJavascriptForRefresh = nil;
}

- (void) loadUrl:(NSURL *)url andJavascript:(NSString *)js
{
    NSURL *currentUrl = nil;
    if (self.wkWebview) {
        currentUrl = self.wkWebview.URL;
    }
    
    if ([[currentUrl absoluteString] isEqualToString:[url absoluteString]]) {
        [self hideWebview];
        [self runJavascript:js];
        self.postLoadJavascriptForRefresh = js;
        [self showWebview];
    } else {
        self.postLoadJavascript = js;
        self.postLoadJavascriptForRefresh = js;
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserStartedLoading object:self];
        [self.wkWebview loadRequest:request];
    }
}

- (void) loadRequest:(NSURLRequest *)request andJavascript:(NSString*)js
{
    self.postLoadJavascript = js;
    self.postLoadJavascriptForRefresh = js;
    [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserStartedLoading object:self];
    [self.wkWebview loadRequest:request];
}

- (void) runJavascript:(NSString *) script
{
    if (!script || script.length == 0) return;
    
    if ([NSThread isMainThread]) {
        [self.wkWebview evaluateJavaScript:script completionHandler:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.wkWebview evaluateJavaScript:script completionHandler:nil];
        });
    }
}

- (void)runJavascriptWithCallback:(id)callback data:(NSDictionary*)data {
    if (!callback) {
        return;
    }
    if ([callback isKindOfClass:[NSString class]]) {
        NSString *js = [LEANUtilities createJsForCallback:callback data:data];
        [self runJavascript:js];
    }
    if ([callback isKindOfClass:[NSArray class]]) {
        for (NSString *callbackItem in callback) {
            if ([callbackItem isKindOfClass:[NSString class]]) {
                NSString *js = [LEANUtilities createJsForCallback:callbackItem data:data];
                [self runJavascript:js];
            }
        }
    }
}

- (void)runCustomCode:(NSDictionary *)query {
    // execute code defined by the CustomCodeHandler
    // call LEANJsCustomCodeExecutor#setHandler to override this default handler
    NSDictionary *data = [LEANJsCustomCodeExecutor execute:query];

    NSString *callback = query[@"callback"];
    if (callback && callback.length > 0) {
        NSString *js = [LEANUtilities createJsForCallback:callback data:data];
        [self runJavascript:js];
    }
}

// is this is the first LEANWebViewController in the navigation stack?
- (BOOL) isRootWebView
{
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:[LEANWebViewController class]]) {
            return vc == self;
        }
    }
    
    return NO;
}

+ (NSInteger) urlLevelForUrl:(NSURL*)url;
{
    // -1 for unknown
    return [medianConfig() urlLevelForUrlUrl:[url absoluteString] ?: @""];
}

+ (NSString*) titleForUrl:(NSURL*)url
{
    MCKMPNavigationTitleRule *rule = [medianConfig() titleRuleForUrlUrl:[url absoluteString] ?: @""];
    if (rule && rule.customTitle) return rule.title;
    return nil;
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if(event.subtype == UIEventSubtypeMotionShake){
        [[NSNotificationCenter defaultCenter] postNotificationName:kGoNativeCoreDeviceDidShake object:nil];
    }
}

#pragma mark - Search Bar Delegate
- (void) searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    NSString *searchText = [searchBar.text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *searchTemplate = self.actionManager.currentSearchTemplateUrl;
    NSURL *url = [NSURL URLWithString:[searchTemplate stringByAppendingString:searchText]];

    [self loadUrl:url];
    
    self.navigationItem.titleView = self.defaultTitleView;
    [self updateNavigationBarItemsAnimated:YES];
}

- (void) searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self searchCanceled];
}

- (void) searchCanceled
{
    self.navigationItem.titleView = self.defaultTitleView;
    [self updateNavigationBarItemsAnimated:YES];
}


#pragma mark - WebView Delegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction preferences:(nonnull WKWebpagePreferences *)preferences decisionHandler:(nonnull void (^)(WKNavigationActionPolicy, WKWebpagePreferences * _Nonnull))decisionHandler  API_AVAILABLE(ios(13.0)) {
    BOOL shouldModifyRequest = [self.customHeadersManager shouldModifyRequest:navigationAction.request webview:webView];
    
    // is target="_blank" and we are allowing window open? Always accept, skipping logic. This makes
    // target="_blank" behave like window.open
    if (navigationAction.targetFrame == nil && medianConfig().configRoot.general.enableWindowOpen) {
        decisionHandler(WKNavigationActionPolicyAllow, preferences);
        return;
    }
    
    BOOL isUserAction = navigationAction.navigationType == WKNavigationTypeLinkActivated || navigationAction.navigationType == WKNavigationTypeFormSubmitted;
    BOOL shouldLoad = [self shouldLoadRequest:navigationAction.request isMainFrame:navigationAction.targetFrame.isMainFrame isUserAction:isUserAction hideWebview:YES windowOpen:NO];
    if (!shouldLoad) {
        decisionHandler(WKNavigationActionPolicyCancel, preferences);
        return;
    }
    
    [self.documentSharer receivedRequest:navigationAction.request];
    
    if (shouldModifyRequest &&
        navigationAction.targetFrame.isMainFrame &&
        ![OFFLINE_URL isEqualToString:navigationAction.request.URL.absoluteString]) {
        NSURLRequest *modifiedRequest = [self.customHeadersManager modifyRequest:navigationAction.request];
        decisionHandler(WKNavigationActionPolicyCancel, preferences);
        [self.wkWebview loadRequest:modifiedRequest];
        return;
    }
    
    BOOL openShareDialog = [navigationAction.request.URL.scheme isEqualToString:@"data"] && ![LEANUtilities isOnePixelImage:navigationAction.request.URL];
    if (@available(iOS 15.0, *)) {
        if (navigationAction.shouldPerformDownload) {
            openShareDialog = [((LEANAppDelegate *)UIApplication.sharedApplication.delegate).bridge shouldDownloadUrlWebView:webView url:navigationAction.request.URL];
        }
    }
    
    if (openShareDialog) {
        [self.documentSharer shareUrl:navigationAction.request.URL fromView:self.wkWebview];
        [self showWebviewWithDelay:0.3]; // Stop loading animation
        decisionHandler(WKNavigationActionPolicyCancel, preferences);
        return;
    }
    
    decisionHandler(WKNavigationActionPolicyAllow, preferences);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
    [self.documentSharer receivedWebviewResponse:navigationResponse.response];
    if (navigationResponse.forMainFrame){
        [self.toolbarManager setUrlMimeType:navigationResponse.response.MIMEType];
    }
    
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *response = (NSHTTPURLResponse *)navigationResponse.response;
        NSString *contentDisposition = [response.allHeaderFields objectForKey:@"Content-Disposition"];
        
        if ([contentDisposition.lowercaseString containsString:@"attachment"]) {
            [self.documentSharer shareUrl:response.URL fromView:self.wkWebview];
            decisionHandler(WKNavigationResponsePolicyCancel);
            return;
        }
    }
    
    if ([self.pdfManager shouldHandleResponse:navigationResponse.response]) {
        [self.pdfManager openPDF:navigationResponse.response.URL wvc:self];
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    
    if (navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyAllow);
        return;
    }
    
    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge webViewHandleURLWebView:webView url:navigationResponse.response.URL];
    
    if ([@"application/vnd.apple.pkpass" isEqualToString:navigationResponse.response.MIMEType]) {
        decisionHandler(WKNavigationResponsePolicyCancel);
        NSURL *url = navigationResponse.response.URL;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideWebview];
            
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

            void (^downloadPass)(void) = ^void() {
                NSURLSessionDataTask *task =  [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self showWebview];
                    });
                    
                    if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
                        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
                        if (httpResponse.statusCode == 200) {
                            NSError *passError;
//                            PKPass *pass = [[PKPass alloc] initWithData:data error:&passError];
                            if (passError) {
                                NSLog(@"Error parsing pass from %@: %@", url, passError);
                            } else {
                                dispatch_async(dispatch_get_main_queue(), ^{
//                                    PKAddPassesViewController *apvc = [[PKAddPassesViewController alloc] initWithPass:pass];
//                                    [[self getTopPresentedViewController] presentViewController:apvc animated:YES completion:nil];
                                });
                            }
                        } else {
                            NSLog(@"Got status %ld when downloading pass from %@", (long)httpResponse.statusCode, url);
                        }
                    } else {
                        NSLog(@"Error getting pass (%@): %@", url, error);
                    }
                }];
                [task resume];
            };
            
            // If using WKWebView on iOS11+, get cookies from WKHTTPCookieStore
            BOOL gettingWKWebviewCookies = NO;
            if (medianConfig().configRoot.general.useWKWebView) {
                if (@available(iOS 11.0, *)) {
                    gettingWKWebviewCookies = YES;
                    WKHTTPCookieStore *cookieStore = [WKWebsiteDataStore defaultDataStore].httpCookieStore;
                    [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> * _Nonnull cookies) {
                        NSMutableArray *cookiesToSend = [NSMutableArray array];
                        for (NSHTTPCookie *cookie in cookies) {
                            if ([LEANUtilities cookie:cookie matchesUrl:url]) {
                                [cookiesToSend addObject:cookie];
                            }
                        }
                        NSDictionary *headerFields = [NSHTTPCookie requestHeaderFieldsWithCookies:cookiesToSend];
                        NSString *cookieHeader = headerFields[@"Cookie"];
                        if (cookieHeader) {
                            [request addValue:cookieHeader forHTTPHeaderField:@"Cookie"];
                        }
                        downloadPass();
                    }];
                }
            }
            if (!gettingWKWebviewCookies) {
                downloadPass();
            }
        });
        return;
    }
    
    if ([@"text/vcard" isEqualToString:navigationResponse.response.MIMEType]) {
        [self.documentSharer shareUrl:navigationResponse.response.URL fromView:self.wkWebview];
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    
    if (@available(iOS 15.0, *)) {
        decisionHandler(WKNavigationResponsePolicyDownload);
        return;
    }
    
    decisionHandler(WKNavigationResponsePolicyCancel);
}

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction didBecomeDownload:(WKDownload *)download  API_AVAILABLE(ios(15.0)) {
    download.delegate = self;
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download  API_AVAILABLE(ios(15.0)) {
    download.delegate = self;
}

- (void)download:(nonnull WKDownload *)download decideDestinationUsingResponse:(nonnull NSURLResponse *)response suggestedFilename:(nonnull NSString *)suggestedFilename completionHandler:(nonnull void (^)(NSURL * _Nullable))completionHandler  API_AVAILABLE(ios(15.0)) {
    NSURL *url = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:suggestedFilename isDirectory:YES];
    completionHandler(url);
}

-(void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type decisionHandler:(void (^)(WKPermissionDecision))decisionHandler  API_AVAILABLE(ios(15.0)){
    if (type == WKMediaCaptureTypeCameraAndMicrophone) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            decisionHandler(granted ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);
        }];
    } else if (type == WKMediaCaptureTypeMicrophone) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            decisionHandler(granted ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);
        }];
    } else {
        decisionHandler(WKPermissionDecisionGrant);
    }
}

- (void)addScriptMessageHandlersInWebView:(WKWebView*)wkWebview {
    [self removeScriptMessageHandlersInWebView:wkWebview];
    // MCKMPWebViewBridge registers itself on both "JSBridge" (legacy) and "medianBridge"
    self.medianBridge = [[MCKMPWebViewBridge alloc] initWithWebView:wkWebview router:self.messageRouter host:self gate:self];
    [wkWebview.configuration.userContentController addScriptMessageHandler:self.fileWriterSharer name:GNFileWriterSharerName];
    [wkWebview.configuration.userContentController addScriptMessageHandler:[LEANWindowOverrideHandler shared] name:LEANWindowOverrideHandlerName];
}

- (void)removeScriptMessageHandlersInWebView:(WKWebView*)wkWebview {
    [wkWebview.configuration.userContentController removeScriptMessageHandlerForName:@"JSBridge"];
    [wkWebview.configuration.userContentController removeScriptMessageHandlerForName:@"medianBridge"];
    [wkWebview.configuration.userContentController removeScriptMessageHandlerForName:GNFileWriterSharerName];
    [wkWebview.configuration.userContentController removeScriptMessageHandlerForName:LEANWindowOverrideHandlerName];
}

// MCKMPWebViewBridgeGate: authorization ahead of any JS bridge routing
- (BOOL)shouldProcessMessageCurrentUrl:(NSString *)currentUrl {
    if (![LEANUtilities checkNativeBridgeUrl:currentUrl]) {
        NSLog(@"URL not authorized for native bridge: %@", currentUrl);
        return NO;
    }
    return YES;
}

-(void)webView:(WKWebView *)webView contextMenuConfigurationForElement:(WKContextMenuElementInfo *)elementInfo completionHandler:(void (^)(UIContextMenuConfiguration * _Nullable))completionHandler {
    UIContextMenuConfiguration *config = [ContextMenuHandler createConfigurationWithUrl:elementInfo.linkURL shareAction:^{
        [self.documentSharer shareUrl:elementInfo.linkURL fromView:webView];
    }];
    completionHandler(config);
}

- (void) handleJSBridgeFunctions:(id)data{
    NSString *currentUrl;
    if (self.wkWebview) {
        currentUrl = self.wkWebview.URL.absoluteString;
    }
    if (![self shouldProcessMessageCurrentUrl:currentUrl]) {
        return;
    }

    NSURL *url;
    NSDictionary *query;
    if([data isKindOfClass:[NSURL class]]){
        url = data;
        query = [LEANUtilities parseQueryParamsWithUrl:url];
    } else if([data isKindOfClass:[NSDictionary class]]) {
        url = [NSURL URLWithString:data[@"medianCommand"]];
        if(!url) return;
        if([data[@"data"] isKindOfClass:[NSDictionary class]]) query = data[@"data"];
    } else return;

    // plugins may intercept commands before routing
    if ([((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge shouldLoadRequestWithURLHost:self url:url query:query]) {
        return;
    }

    if([data isKindOfClass:[NSDictionary class]]) {
        MCKMPBridgeMessage *message = [self.messageRouter parseJsonBodyJsonBody:data];
        if (message) [self.messageRouter dispatchMessage:message host:self responder:self];
    } else {
        [self.messageRouter routeUrl:url.absoluteString host:self responder:self];
    }
}

// currently, sender is used to receive a selected UIBarButtonItem from the action bar
- (BOOL)shouldLoadRequest:(NSURLRequest*)request isMainFrame:(BOOL)isMainFrame isUserAction:(BOOL)isUserAction hideWebview:(BOOL)hideWebview windowOpen:(BOOL)windowOpen
{
    MCKMPMutableConfigState *appConfig = medianConfig();
    NSURL *url = [request URL];
    NSString *urlString = [url absoluteString];
    NSString* hostname = [url host];
    
//    NSLog(@"should start load %@ main %d action %d", url, isMainFrame, isUserAction);
    
    // simulator
    if ([url.scheme isEqualToString:@"gonative.io"]) {
        return YES;
    }
    
    // local
    if ([url.host isEqualToString:@"offline"]) {
        return YES;
    }
    
    // show share dialog for base64 urls
    if ([url.scheme isEqualToString:@"data"]) {
        return YES;
    }
    
    // blob download
    if (urlString.length == 0) {
        // for some reason we will get an empty url before the actual blob url on iOS 11
        return NO;
    }
    
    // Only start blob downloads on the main frame
    if ([url.scheme isEqualToString:@"blob"] && isMainFrame) {
        [self.fileWriterSharer downloadBlobUrl:url filename:nil callback:nil];
        return NO;
    }
    
    if (appConfig.configRoot.general.injectMedianJS) {
        // inject GoNative JS Bridge Library if regex matches
        if([LEANUtilities checkNativeBridgeUrl:urlString]){
            if(!self.JSBridgeScript){
                NSURL *GNJSBridgeFile = [[NSBundle mainBundle] URLForResource:@"GoNativeJSBridgeLibrary" withExtension:@"js"];
                if(GNJSBridgeFile)
                    self.JSBridgeScript = [NSString stringWithContentsOfURL:GNJSBridgeFile encoding:NSUTF8StringEncoding error:nil];
            }
            if(self.JSBridgeScript){
                WKUserScript *GNJSBridgeLibrary = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:self.JSBridgeScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
                [self.wkWebview.configuration.userContentController addUserScript:GNJSBridgeLibrary];

                // load plugins' js script (polyfills via median-core injector), document-start like legacy
                MCKMPPluginJSInjector *injector = [[MCKMPPluginJSInjector alloc] initWithAssetReader:[[MCKMPIOSAssetReader alloc] init]];
                NSString *pluginScript = [injector combinedScript];
                if (pluginScript) {
                    WKUserScript *pluginUserScript = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:pluginScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
                    [self.wkWebview.configuration.userContentController addUserScript:pluginUserScript];
                }
            }
        } else {
            NSString *emptyJSBridgeScript = @"gonative = null";
            WKUserScript *GNJSBridgeLibrary = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:emptyJSBridgeScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
            [self.wkWebview.configuration.userContentController addUserScript:GNJSBridgeLibrary];
        }
    }
    
    if ([url.scheme isEqualToString:@"gonative-bridge"]) {
        NSString *queryString = url.query;
        if (!queryString) return NO;
        
        NSArray *queryComponents = [queryString componentsSeparatedByString:@"&"];
        for (NSString *keyValue in queryComponents) {
            NSArray *pairComponents = [keyValue componentsSeparatedByString:@"="];
            NSString *key = [[pairComponents firstObject] stringByRemovingPercentEncoding];
            if ([key isEqualToString:@"json"] && [pairComponents count] == 2) {
                NSString *json = [[pairComponents lastObject] stringByRemovingPercentEncoding];
                
                NSArray *parsedJson = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                if (![parsedJson isKindOfClass:[NSArray class]]) return NO;
                
                for (NSDictionary *entry in parsedJson) {
                    if (![entry isKindOfClass:[NSDictionary class]]) continue;
                    
                    NSString *command = entry[@"command"];
                    if (![command isKindOfClass:[NSString class]]) continue;
                    
                    if ([command isEqualToString:@"pop"]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // it's safe to call popViewControllerAnimated even if we are only one on the stack
                            [self.navigationController popViewControllerAnimated:YES];
                        });
                    } else if ([command isEqualToString:@"clearPools"]) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerClearPools object:self];
                    }
                }
            }
        }
    }
    
    // JS Bridge Commands
    if ([@"gonative" isEqualToString:url.scheme] || [@"median" isEqualToString:url.scheme]) {
        [self handleJSBridgeFunctions:url];
        return NO;
    }
    
    // tel links
    if ([url.scheme isEqualToString:@"tel"]) {
        NSString *telNumber = url.resourceSpecifier;
        if ([telNumber length] > 0) {
            NSURL *telPromptUrl = [NSURL URLWithString:[NSString stringWithFormat:@"telprompt:%@", telNumber]];
            if ([[UIApplication sharedApplication] canOpenURL:telPromptUrl]) {
                [[UIApplication sharedApplication] openURL:telPromptUrl options:@{} completionHandler:nil];
            } else if ([[UIApplication sharedApplication] canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
        }
        return NO;
    }
    
    // mailto links
    if ([url.scheme isEqualToString:@"mailto"]) {
        if ([MFMailComposeViewController canSendMail]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // parse the mailto link
                NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];

                NSMutableArray *toRecipients = [NSMutableArray array];
                NSArray *recipients = [components.path componentsSeparatedByString:@","];
                for (NSString *recipient in recipients) {
                    if (recipient.length > 0) {
                        [toRecipients addObject:recipient];
                    }
                }
                
                MFMailComposeViewController *mc = [[MFMailComposeViewController alloc] init];
                mc.mailComposeDelegate = self;
                
                for (NSURLQueryItem *item in components.queryItems) {
                    if ([[item.name lowercaseString] isEqualToString: @"subject"]) {
                        [mc setSubject:item.value];
                    } else if ([[item.name lowercaseString]isEqualToString:@"body"]) {
                        [mc setMessageBody:item.value isHTML:NO];
                    } else if ([[item.name lowercaseString] isEqualToString:@"to"]) {
                        // append to array, do not replace
                        [toRecipients addObjectsFromArray:[item.value componentsSeparatedByString:@","]];
                    } else if ([[item.name lowercaseString] isEqualToString:@"cc"]) {
                        [mc setCcRecipients:[item.value componentsSeparatedByString:@","]];
                    } else if ([[item.name lowercaseString] isEqualToString:@"bcc"]) {
                        [mc setBccRecipients:[item.value componentsSeparatedByString:@","]];
                    }
                }
                [mc setToRecipients:toRecipients];
                [self presentViewController:mc animated:YES completion:nil];
            });
        } else {
            NSLog(@"MFMailComposeViewController cannot send mail. Opening mailto url in mail app");
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        return NO;
    }
    
    // sms links
    if ([url.scheme isEqualToString:@"sms"]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return NO;
    }
    
    // always allow iframes to load
    if (!isMainFrame && ![urlString isEqualToString:[[request mainDocumentURL] absoluteString]]) {
        return YES;
    }
    
    [[LEANUrlInspector sharedInspector] inspectUrl:url];

    // check redirects
    NSString *to = [appConfig redirectTargetForUrlUrl:urlString];
    if (to && ![MCKMPUrlUtils.shared urlsMatchIgnoreTrailingUrl1:to url2:urlString]) {
        url = [NSURL URLWithString:to];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadUrl:url];
        });
        return NO;
    }

    // log out by clearing cookies
    if (urlString && [urlString caseInsensitiveCompare:@"file://gonative_logout"] == NSOrderedSame) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self logout];
        });
        return NO;
    }
    
    // twitter app
    if ([hostname isEqualToString:@"twitter.com"] && [[[request URL] path] isEqualToString:@"/intent/tweet"])
    {
        NSDictionary* dict = [LEANUtilities dictionaryFromQueryString:[[request URL] query]];
        
        NSURL* url = [NSURL URLWithString:
                      [LEANUtilities addQueryStringToUrlString:@"twitter://post?"
                                                withDictionary:@{@"message": [NSString stringWithFormat:@"%@ %@ @%@",
                                                                              dict[@"text"],
                                                                              dict[@"url"],
                                                                              dict[@"via"]]}]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[UIApplication sharedApplication] canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            } else {
                [[UIApplication sharedApplication] openURL:request.URL options:@{} completionHandler:nil];
            }
        });
        
        return NO;
    }
    
    // external sites: don't launch if in iframe.
    if (isUserAction || (isMainFrame && ![[request URL] matchesPathOf:[self.currentRequest URL]])) {
        // first check regexInternalExternal
        BOOL shouldHandleUrl = [self.regexRulesManager shouldHandleRequest:request];
        if (!shouldHandleUrl) {
            return NO;
        }
    }
    
    // Starting here, we are going to load the request, but possibly in a different webviewcontroller depending on the structured nav level
    if (self.restoreBrightnessOnNavigation) {
        if (self.savedScreenBrightness >= 0) {
            [UIScreen mainScreen].brightness = self.savedScreenBrightness;
        }
        self.restoreBrightnessOnNavigation = NO;
    }
    
    NSInteger newLevel = [LEANWebViewController urlLevelForUrl:url];
    if (self.urlLevel >= 0 && newLevel >= 0) {
        if (newLevel > self.urlLevel || windowOpen) {
            // push a new controller
            LEANWebViewController *newvc = [self.storyboard instantiateViewControllerWithIdentifier:@"webviewController"];
            newvc.initialUrl = url;
            newvc.postLoadJavascript = self.postLoadJavascript;
            self.postLoadJavascript = nil;
            self.postLoadJavascriptForRefresh = nil;
            
            NSMutableArray *controllers = [self.navigationController.viewControllers mutableCopy];
            while (![[controllers lastObject] isKindOfClass:[LEANWebViewController class]]) {
                [controllers removeLastObject];
            }
            [controllers addObject:newvc];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.navigationController setViewControllers:controllers animated:YES];
            });
            
            return NO;
        }
        else if (newLevel < self.urlLevel) {
            // find controller on top of the first controller with a lower-numbered level
            NSArray *vcs = self.navigationController.viewControllers;
            LEANWebViewController *wvc = self;
            for (NSInteger i = vcs.count - 1; i >= 0; i--) {
                if ([vcs[i] isKindOfClass:[LEANWebViewController class]]) {
                    if (newLevel > ((LEANWebViewController*)vcs[i]).urlLevel) {
                        break;
                    }
                    
                    // save into as the 'previous to last' controller
                    wvc = vcs[i];
                }
            }
            
            if (wvc != self) {
                wvc.urlLevel = newLevel;
                if (self.postLoadJavascript) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [wvc loadRequest:request andJavascript:self.postLoadJavascript];
                    });
                    self.postLoadJavascript = nil;
                    self.postLoadJavascriptForRefresh = nil;
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [wvc loadRequest:request];
                    });
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.navigationController popToViewController:wvc animated:YES];
                });
                return NO;
            }
        }
    }
    
    
    // Starting here, the request will be loaded in this webviewcontroller
    // pop to the top webviewcontroller in the stack
    NSMutableArray *controllers = [self.navigationController.viewControllers mutableCopy];
    BOOL changedControllerStack = NO;
    while (controllers && controllers.count > 0 &&
           ![[controllers lastObject] isKindOfClass:[LEANWebViewController class]]) {
        [controllers removeLastObject];
        changedControllerStack = YES;
    }
    if (changedControllerStack) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController setViewControllers:controllers animated:YES];
        });
    }
    
    if (newLevel >= 0) {
        self.urlLevel = newLevel;
    }
    
    NSString *newTitle = [LEANWebViewController titleForUrl:url];
    if (newTitle) {
        self.navigationItem.title = newTitle;
    }
    
    
    // save request for various functions that require the current request
    NSURLRequest *previousRequest = self.currentRequest;
    self.currentRequest = request;
    // save for html interception
    [LEANWebviewInterceptTracker sharedTracker].currentRequest = request;
    
    // update title image, tabs, etc
    [self checkPreNavigationForUrl:request.URL];
    
    // check to see if the webview exists in pool. Swap it in if it's not the same url.
    UIView *poolWebview = nil;
    LEANWebViewPoolDisownPolicy poolDisownPolicy;
    poolWebview = [[LEANWebViewPool sharedPool] webviewForUrl:url policy:&poolDisownPolicy];
    
    if (poolWebview && poolDisownPolicy == LEANWebViewPoolDisownPolicyAlways) {
        self.isPoolWebview = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToWebView:poolWebview showImmediately:YES];
            self.didLoadPage = YES;
            [self checkNavigationForUrl:url];
        });
        [[LEANWebViewPool sharedPool] disownWebview:poolWebview];
        [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserFinishedLoading object:self];
        return NO;
    }
    
    if (poolWebview && poolDisownPolicy == LEANWebViewPoolDisownPolicyNever) {
        self.isPoolWebview = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToWebView:poolWebview showImmediately:YES];
            self.didLoadPage = YES;
            [self checkNavigationForUrl:url];
        });
        return NO;
    }
    
    if (poolWebview && poolDisownPolicy == LEANWebViewPoolDisownPolicyReload &&
        ![[request URL] matchesPathOf:[previousRequest URL]]) {
        self.isPoolWebview = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self switchToWebView:poolWebview showImmediately:YES];
            self.didLoadPage = YES;
            [self checkNavigationForUrl:url];
        });
        return NO;
    }
    
    if (self.isPoolWebview) {
        // if we are here, either the policy is reload and we are reloading the page, or policy is never but we are going to a different page. So take ownership of the webview.
        [[LEANWebViewPool sharedPool] disownWebview:self.wkWebview];
        self.isPoolWebview = NO;
    }
    
    // Do not hide the webview if url.fragment exists and the url is the same.
    // here sometimes is an issue with single-page apps where shouldLoadRequest
    // is called for SPA page loads if there is a fragment (anchor). We will never get an sort of page finished callback, so the page
    // is always hidden.
    BOOL hide = hideWebview;
    if (hide && url.fragment) {
        NSURL *currentUrl = self.currentRequest.URL;
        if (currentUrl && [currentUrl matchesIgnoreAnchor:url]) {
            hide = NO;
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (hide) [self hideWebview];
        [self setNavigationButtonStatus];
    });
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserStartedLoading object:self];
    
    return YES;
}

- (void)switchToWebView:(UIView*)newView showImmediately:(BOOL)showImmediately
{
    [self.eventsManager clearSubscriptions];

    UIView *oldView;
    if (self.wkWebview) {
        oldView = self.wkWebview;
        [self removeScriptMessageHandlersInWebView:self.wkWebview];
        
        // remove KVO
        @try {
            [oldView removeObserver:self forKeyPath:@"URL"];
            [oldView removeObserver:self forKeyPath:@"canGoBack"];
            [oldView removeObserver:self forKeyPath:@"canGoForward"];
        }
        @catch (NSException * __unused exception) {
        }
    }
    
    [self hideWebview];
    
    [self removePullRefresh];
    
    UIScrollView *scrollView;
    if ([newView isKindOfClass:[NSClassFromString(@"WKWebView") class]]) {
        self.wkWebview = (WKWebView*)newView;
        self.wkWebview.navigationDelegate = self;
        self.wkWebview.UIDelegate = self;
        self.wkWebview.scrollView.delegate = self;
        scrollView = self.wkWebview.scrollView;
        
        // add KVO for single-page app url changes
        [newView addObserver:self forKeyPath:@"URL" options:0 context:nil];
        [newView addObserver:self forKeyPath:@"title" options:0 context:nil];
        [newView addObserver:self forKeyPath:@"canGoBack" options:0 context:nil];
        [newView addObserver:self forKeyPath:@"canGoForward" options:0 context:nil];
        
        self.wkWebview.allowsBackForwardNavigationGestures = medianConfig().configRoot.navigation.swipeGestures;
        self.fileWriterSharer.webView = newView;
        [self addScriptMessageHandlersInWebView:self.wkWebview];
    } else {
        return;
    }
    
    // scroll before swapping to help reduce jank
    [scrollView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
    
    if (oldView != newView) {
        if (oldView) {
            newView.frame = oldView.frame;
            [self.webviewContainer insertSubview:newView aboveSubview:oldView];
            [oldView removeFromSuperview];
        } else {
            newView.frame = self.webviewContainer.frame;
            [self.webviewContainer insertSubview:newView atIndex:0];
        }
        
        // add layout constriants to constainer view
        [self.webviewContainer addConstraint:[NSLayoutConstraint constraintWithItem:newView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.webviewContainer attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        [self.webviewContainer addConstraint:[NSLayoutConstraint constraintWithItem:newView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.webviewContainer attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
        [self.webviewContainer addConstraint:[NSLayoutConstraint constraintWithItem:newView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.webviewContainer attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
        [self.webviewContainer addConstraint:[NSLayoutConstraint constraintWithItem:newView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.webviewContainer attribute:NSLayoutAttributeRight multiplier:1 constant:0]];

    }
    [self adjustInsets];
    // re-scroll after adjusting insets
    [scrollView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
    
    if (self.postLoadJavascript) {
        [self runJavascript:self.postLoadJavascript];
        self.postLoadJavascript = nil;
    }
    
    // fix for black boxes
    for (UIView *view in scrollView.subviews) {
        [view setNeedsDisplayInRect:newView.bounds];
    }
    
    if (showImmediately) {
        [self showWebview];
    }
    
    if (medianConfig().configRoot.navigation.iosPullToRefresh) {
        [self addPullToRefresh];
    }

    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge switchToWebViewNewView:newView host:self];
}

// To detect single-page app navigation in WKWebView
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if (object == self.wkWebview) {
        NSURL *url = self.wkWebview.URL;

        if ([keyPath isEqualToString:@"URL"]) {
            if (url) {
                [self checkPreNavigationForUrl:url];
                [self checkNavigationForUrl:url];
                [self.actionManager didLoadUrl:url];
            }
        }
        if ([keyPath isEqualToString:@"title"]) {
            // Update page title
            if (self.wkWebview.title) {
                [self checkNavigationTitleImageForUrl:url];
            }
        }
        if ([keyPath isEqualToString:@"canGoBack"]) {
            // we need a separate observe canGoBack because it seems to update after URL
            [self.toolbarManager didLoadUrl:url];
        }
        if ([keyPath isEqualToString:@"canGoForward"]) {
            // we need a separate observe canGoForward because it seems to update after URL
            [self.toolbarManager didLoadUrl:url];
        }
    }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
    // main-frame document replaced, so the previous page's subscriptions no longer apply.
    // Same-document navigations do not reach this delegate method.
    [self.eventsManager clearSubscriptions];
    [self didStartLoad];
}

- (void)didStartLoad
{
    self.startedLoading = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!medianConfig().configRoot.navigation.iosPullToRefresh) {
            [self removePullRefresh];
        }
        
        [self.customActionButton setEnabled:NO];
        
        [self.timer invalidate];
        self.timer = [NSTimer timerWithTimeInterval:0.05 target:self selector:@selector(checkReadyStatus) userInfo:nil repeats:YES];
        [self.timer setTolerance:0.02];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSDefaultRunLoopMode];
        
        // remove share button
        if (self.shareButton) {
            self.shareButton = nil;
            [self updateNavigationBarItemsAnimated:YES];
        }
        
        // stop watching location
        [self.locationManager stopUpdatingLocation];
        
        [self updateViewBackgroundColor];
    });
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [self didFinishLoad];

    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge webViewDidFinishNavigationWebView:webView navigation:navigation host:self];
}

- (void)didFinishLoad
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showWebview];

        MCKMPMutableConfigState *appConfig = medianConfig();

        NSURL *url = nil;
        if (self.wkWebview) {
            url = self.wkWebview.URL;
        }
        
        // don't do any more processing or set didloadpage if we are showing an offline page
        if (!url || [url.host isEqualToString:@"offline"]) {
            [self addPullToRefresh];
            self.didLoadPage = NO;
            return;
        }
        
        self.didLoadPage = YES;
        
        [[LEANUrlInspector sharedInspector] inspectUrl:url];
        [self setNavigationButtonStatus];

        [LEANUtilities overrideGeolocation:self.wkWebview];
        self.logManager = [[GNLogManager alloc] initWithWebview:self.wkWebview enabled:appConfig.configRoot.developmentTools.enableWebConsoleLogs];

        // update navigation title
        if (appConfig.configRoot.navigation.useWebpageTitle) {
            if (self.wkWebview) {
                self.nav.title = self.wkWebview.title;
            }
        }

        // track login/signup page visits (forms intercept)
        NSString *loginUrl = appConfig.configRoot.forms.loginConfig.interceptUrl;
        NSString *signupUrl = appConfig.configRoot.forms.signupConfig.interceptUrl;
        self.visitedLoginOrSignup = (loginUrl && [url matchesPathOf:[NSURL URLWithString:loginUrl]]) ||
            (signupUrl && [url matchesPathOf:[NSURL URLWithString:signupUrl]]);

        // post-load javascript
        if (appConfig.configRoot.general.postLoadJavascript) {
            [self runJavascript:appConfig.configRoot.general.postLoadJavascript];
        }

        // tabs
        [self checkNavigationForUrl: url];
        
        // actions
        [self.actionManager didLoadUrl:url];
        
        // post-load js
        if (self.postLoadJavascript) {
            NSString *js = self.postLoadJavascript;
            self.postLoadJavascript = nil;
            [self runJavascript:js];
        }
        
        // post notification
        [[NSNotificationCenter defaultCenter] postNotificationName:kLEANWebViewControllerUserFinishedLoading object:self];
        
        // document sharing
        if (!appConfig.configRoot.navigation.iosDisableDocumentOpenWith &&
            [self.documentSharer isSharableRequest:self.currentRequest]) {
            if (!self.shareButton) {
                self.shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(sharePressed:)];
            }
        } else {
            self.shareButton = nil;
        }

        BOOL doNativeBridge = YES;
        if (url) {
            doNativeBridge = [LEANUtilities checkNativeBridgeUrl:[url absoluteString]];
        }
        
        // send device info
        if (doNativeBridge) {
            [self runGonativeDeviceInfoWithCallback:@"median_device_info"];
            [self runGonativeDeviceInfoWithCallback:@"gonative_device_info"];
        }
        
        // save session cookies as persistent
        NSUInteger forceSessionCookieExpiry = appConfig.configRoot.general.forceSessionCookieExpiry;
        if (forceSessionCookieExpiry > 0) {
            NSHTTPCookieStorage *cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *cookie in [cookieStore cookiesForURL:url]) {
                if (cookie.expiresDate == nil || cookie.sessionOnly) {
                    NSMutableDictionary *cookieProperties = [cookie.properties mutableCopy];
                    cookieProperties[NSHTTPCookieExpires] = [[NSDate date] dateByAddingTimeInterval:forceSessionCookieExpiry];
                    cookieProperties[NSHTTPCookieMaximumAge] = [NSString stringWithFormat:@"%lu", (unsigned long)forceSessionCookieExpiry];
                    [cookieProperties removeObjectForKey:@"Created"];
                    [cookieProperties removeObjectForKey:NSHTTPCookieDiscard];
                    NSHTTPCookie *newCookie = [NSHTTPCookie cookieWithProperties:cookieProperties];
                    [cookieStore setCookie:newCookie];
                }
            }
            
            // do same for wkwebview
            WKHTTPCookieStore *wkCookieStore = self.wkWebview.configuration.websiteDataStore.httpCookieStore;
            [wkCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> * _Nonnull arrCookies) {
                for (NSHTTPCookie *cookie in arrCookies) {
                    if(cookie.expiresDate == nil || cookie.sessionOnly){
                        NSMutableDictionary *cookieProperties = [cookie.properties mutableCopy];
                        cookieProperties[NSHTTPCookieExpires] = [[NSDate date] dateByAddingTimeInterval:forceSessionCookieExpiry];
                        cookieProperties[NSHTTPCookieMaximumAge] = [NSString stringWithFormat:@"%lu", (unsigned long)forceSessionCookieExpiry];
                        [cookieProperties removeObjectForKey:@"Created"];
                        [cookieProperties removeObjectForKey:NSHTTPCookieDiscard];
                        NSHTTPCookie *newCookie = [NSHTTPCookie cookieWithProperties:cookieProperties];
                        [wkCookieStore setCookie:newCookie completionHandler:nil];
                    }
                }
            }];
        }
        
        // persist previous status of statusbar and body bg color matching
        BOOL enableMatching = [[NSUserDefaults standardUserDefaults] boolForKey:@"matchStatusBarToBodyBgColor"];
        if (enableMatching) {
            [LEANUtilities matchStatusBarToBodyBackgroundColor:self.wkWebview enabled:enableMatching];
        }
        
        // set initial css theme
        NSString *mode = [[NSUserDefaults standardUserDefaults] objectForKey:@"darkMode"];
        [self setCssTheme:mode ?: appConfig.configRoot.styling.iosDarkMode andPersistData:NO];
        
        [self updateViewBackgroundColor];
        
        [self runJavascriptWithCallback:@[@"median_library_ready", @"gonative_library_ready"] data:nil];
    });
}

- (void)handleDeeplinkUrl:(NSURL *)url {
    if (!url) {
        return;
    }
    
    if (self.didLoadPage || self.initialUrl != nil) {
        [self loadUrl:url];
    } else {
        self.initialUrl = url;
    }
}

-(void)runGonativeDeviceInfoWithCallback:(NSString*)callback {
    if(!callback) return;
    
    LEANAppDelegate *appDelegate = (LEANAppDelegate*)[UIApplication sharedApplication].delegate;
    
    NSMutableDictionary *additionalData = [NSMutableDictionary dictionary];
    if(appDelegate.apnsToken)
        additionalData[@"apnsToken"] = appDelegate.apnsToken;
    
    [self runGonativeInfoWithCallback:callback additionalData:additionalData];
}

-(void)runGonativeInfoWithCallback:(NSString*)callback additionalData:(NSDictionary *)additionalData {
    NSMutableDictionary *toSend = [NSMutableDictionary dictionary];
    NSDictionary *installation = [LEANInstallation info];
    [toSend addEntriesFromDictionary:installation];
    if (additionalData)
        [toSend addEntriesFromDictionary:additionalData];
    
    NSString *jsCallback = [LEANUtilities createJsForCallback:callback data:toSend];
    if (jsCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self runJavascript:jsCallback];
        });
    }
}

-(void)runKeyboardInfoWithCallback:(NSString*)callback {
    if(!callback) return;
    
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    data[@"visible"] = @(self.keyboardVisible);
    
    CGFloat keyboardWidth = self.keyboardRect.size.width;
    CGFloat keyboardHeight = self.keyboardRect.size.height;
    data[@"keyboardWindowSize"] = @{
        @"width": @(keyboardWidth),
        @"height": @(keyboardHeight)
    };
    
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    data[@"visibleWindowSize"] = @{
        @"width": @(screenWidth),
        @"height": @(screenHeight - keyboardHeight)
    };
    
    NSString *js = [LEANUtilities createJsForCallback:callback data:data];
    if (js) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self runJavascript:js];
        });
    }
}

- (BOOL)handleNewWindowRequest:(NSURLRequest *)request initialWebview:(WKWebView *)initialWebview {
    if (request) {
        BOOL shouldLoad = [self shouldLoadRequest:request isMainFrame:YES isUserAction:YES hideWebview:NO windowOpen:YES];
        if (!shouldLoad) {
            return NO;
        }
    }
    
    MCKMPMutableConfigState *appConfig = medianConfig();

    if (!appConfig.configRoot.general.enableWindowOpen) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadRequest:request];
        });
        return NO;
    }

    MCKMPMaxWindowsConfig *maxWindows = appConfig.maxWindows;
    if (maxWindows.autoClose && _currentWindows == maxWindows.numWindows &&
        [[NSURL URLWithString:appConfig.initialUrl] matchesIgnoreAnchor:request.URL]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LEANWebViewController *vc = self.navigationController.viewControllers.firstObject;
            [self loadRequest:request];
            [vc switchToWebView:self.wkWebview showImmediately:YES];
            [self.navigationController popToRootViewControllerAnimated:NO];
            
        });
        return NO;
    }
    
    LEANWebViewController *newvc = [self.storyboard instantiateViewControllerWithIdentifier:@"webviewController"];
    newvc.initialUrl = request.URL;
    newvc.isWindowOpen = YES;
    newvc.urlLevel = self.urlLevel;
    
    if (initialWebview) {
        [LEANUtilities configureWebView:initialWebview];
        newvc.initialWebview = initialWebview;
    }
    
    NSMutableArray *controllers = [self.navigationController.viewControllers mutableCopy];
    while (![[controllers lastObject] isKindOfClass:[LEANWebViewController class]]) {
        [controllers removeLastObject];
    }
    [controllers addObject:newvc];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.navigationController setViewControllers:controllers animated:YES];
    });
    
    return YES;
}

- (WKWebView*)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    WKWebView *newWebview = [[NSClassFromString(@"WKWebView") alloc] initWithFrame:self.wkWebview.frame configuration:configuration];
    BOOL handled = [self handleNewWindowRequest:navigationAction.request initialWebview:newWebview];
    if (handled) {
        return newWebview;
    }
    return nil;
}

-(void)webViewDidClose:(WKWebView *)webView
{
    if (webView != self.wkWebview) return;
    
    NSArray *vcs = self.navigationController.viewControllers;
    LEANWebViewController *popTo = nil;
    // find the top webviewcontroller that is not self
    for (NSInteger i = vcs.count - 1; i >= 0; i--) {
        if ([vcs[i] isKindOfClass:[LEANWebViewController class]] && vcs[i] != self) {
            popTo = vcs[i];
            break;
        }
    }
    
    if (popTo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popToViewController:popTo animated:YES];
        });
    } else {
        NSString *initialUrlPref = [self.configPreferences getInitialUrl];
        if (initialUrlPref) {
            [self loadUrl:[NSURL URLWithString:initialUrlPref]];
        } else {
            [self loadUrl:[NSURL URLWithString:medianConfig().initialUrl]];
        }
    }
}

    - (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)message defaultText:(nullable NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * __nullable result))completionHandler
    {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
        [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = defaultText;
        }];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"button-cancel", @"Button: Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            completionHandler(nil);
        }]];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"button-ok", @"Button: OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *input = ((UITextField *)alertController.textFields.firstObject).text;
            completionHandler(input);
        }]];
        [[self getTopPresentedViewController] presentViewController:alertController animated:YES completion:^{}];
    }

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"button-ok", @"Button: OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler();
    }];
    [alert addAction:okAction];
    
    // There is a chance that a view controller is already being presented, e.g. if a drop-down box
    // on iPad is open, and selecting an item triggers a javascript alert. That's why we don't just call
    // [self presentViewController:]
    [[self getTopPresentedViewController] presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"button-ok", @"Button: OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(YES);
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"button-cancel", @"Button: Cancel") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(NO);
    }];
    [alert addAction:cancelAction];
    [alert addAction:okAction];
    
    [[self getTopPresentedViewController] presentViewController:alert animated:YES completion:nil];

}

-(UIViewController*)getTopPresentedViewController {
    UIViewController *vc = self;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

- (void)checkReadyStatus
{
    // if interactiveDelay is specified, then look for readyState=interactive, and show webview
    // with a delay. If not specified, wait for readyState=complete.
    NSNumber *interactiveDelay = medianConfig().configRoot.styling.transitionInteractiveDelayMax;
    
    void (^readyStateBlock)(id, NSError*) = ^(id status, NSError *error) {
        // we keep track of startedLoading because loading is only really finished when we have gone to
        // "loading" or "interactive" before going to complete. When the web page first starts loading,
        // it will be in "complete", then "loading", "interactive", and finally "complete".
        
        if (![status isKindOfClass:[NSString class]]) {
            return;
        }
        
        if ([status isEqualToString:@"loading"] || (!interactiveDelay && [status isEqualToString:@"interactive"])){
            self.startedLoading = YES;
        }
        else if ((interactiveDelay && [status isEqualToString:@"interactive"])
                 || (self.startedLoading && [status isEqualToString:@"complete"])) {
            
            self.didLoadPage = YES;
            
            if ([status isEqualToString:@"interactive"]){
                // note: doubleValue will be 0 if interactiveDelay is null
                [self showWebviewWithDelay:[interactiveDelay doubleValue]];
            }
            else {
                [self showWebview];
            }
        }
    };
    
    if (self.wkWebview) {
        [self.wkWebview evaluateJavaScript:@"document.readyState" completionHandler:readyStateBlock];
    }
}

- (void)hideWebview
{
    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge hideWebViewWithRunnerHost:self];

    if (medianConfig().configRoot.styling.disableAnimations) return;
    
    self.wkWebview.alpha = self.hideWebviewAlpha;
    self.wkWebview.userInteractionEnabled = NO;
    
    [self.loadingSpinnerManager startAnimationWithWvc:self];
    
    // Show webview after 10 seconds just in case we never get a page finished callback
    // Otherwise, users may be stuck forever on the loading animation
    [self showWebviewWithDelay:10.0];
}

- (void)showWebview
{
    // cancel any other pending calls to showWebView
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showWebview) object:nil];
    
    self.startedLoading = NO;
    [self.timer invalidate];
    self.timer = nil;
    self.wkWebview.userInteractionEnabled = YES;
    
    [self.loadingSpinnerManager stopAnimation];
    
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^(void){
        self.wkWebview.alpha = 1.0;
    } completion:^(BOOL finished){
        [[LEANLaunchScreenManager sharedManager] hideAfterDelay:0.3];
    }];
}

- (void)showWebviewWithDelay:(NSTimeInterval)delay
{
    [self performSelector:@selector(showWebview) withObject:nil afterDelay:delay];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self didFailLoadWithError:error isProvisional:NO];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self didFailLoadWithError:error isProvisional:YES];
}

- (void)didFailLoadWithError:(NSError*)error isProvisional:(BOOL)isProvisional
{
    // show webview unless navigation was canceled, which is most likely due to a different page being requested
    if (![error.domain isEqualToString:NSURLErrorDomain] || error.code != NSURLErrorCancelled) {
        [self showWebview];
    }
    
    if ([[error domain] isEqualToString:NSURLErrorDomain]) {
        if (!medianConfig().configRoot.navigation.iosShowOfflinePage.boolValue)
            return;
        
        if ([error code] == NSURLErrorCannotFindHost || [error code] == NSURLErrorNotConnectedToInternet ||
            (isProvisional && [error code] == NSURLErrorTimedOut)) {
            [self showOfflinePage];
        }
    }
}

- (void) showOfflinePage
{
    NSURL *offlineFile = [[NSBundle mainBundle] URLForResource:@"offline" withExtension:@"html"];
    NSString *html = [NSString stringWithContentsOfURL:offlineFile encoding:NSUTF8StringEncoding error:nil];
    [self.wkWebview loadHTMLString:html baseURL:[NSURL URLWithString:OFFLINE_URL]];
}

- (void) showSidebarNavButton {
    NSString *icon = medianConfig().configRoot.navigation.sidebarNavigation.menuIcon ?: @"fas fa-bars";
    NSString *label = NSLocalizedString(@"button-menu", @"Button: Menu");
    self.navButton = [self.actionManager createNavBarButtonWithLabel:label icon:icon target:self action:@selector(showMenu)];
}

- (void) setNavigationButtonStatus
{
    self.backButton.enabled = self.wkWebview.canGoBack;
    self.forwardButton.enabled = self.wkWebview.canGoForward;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSDictionary*)getConnectivity
{
    LEANAppDelegate *appDelegate = (LEANAppDelegate*)[UIApplication sharedApplication].delegate;
    Reachability *reachability = appDelegate.internetReachability;
    NetworkStatus status = [reachability currentReachabilityStatus];
    NSString *statusString;
    NSNumber *connected;

    switch (status) {
        case NotReachable:
            statusString = @"DISCONNECTED";
            connected = [NSNumber numberWithBool:NO];
            break;
        case ReachableViaWiFi:
            statusString = @"WIFI";
            connected = [NSNumber numberWithBool:YES];
            break;
        case ReachableViaWWAN:
            statusString = @"MOBILE";
            connected = [NSNumber numberWithBool:YES];
            break;
            
        default:
            statusString = @"UNKNOWN";
            break;
    }
    
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:2];
    [result setObject:statusString forKey:@"type"];
    if (connected) {
        [result setObject:connected forKey:@"connected"];
    }
    
    return result;
}

#pragma mark - MFMailComposeViewControllerDelegate
- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Location

-(void)checkLocationPermissionWithBlock:(void (^)(void))block
{
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        NSError *error = [NSError errorWithDomain:kCLErrorDomain code:kCLErrorDenied userInfo:nil];
        [self locationManager:self.locationManager didFailWithError:error];
    } else if (status == kCLAuthorizationStatusNotDetermined) {
        self.locationPermissionBlock = block;
        [self.locationManager requestWhenInUseAuthorization];
    } else {
        block();
    }
}

-(void)requestLocation
{
    [self checkLocationPermissionWithBlock:^{
        [self.locationManager requestLocation];
        if (self.locationManager.location) {
            [self receivedLocation:self.locationManager.location];
        }
    }];
}

-(void)startWatchingLocation
{
    [self checkLocationPermissionWithBlock:^{
        [self.locationManager startUpdatingLocation];
    }];
}

-(void)stopWatchingLocation
{
    [self.locationManager stopUpdatingLocation];
}

-(void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    if (status != kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestLocation];
    }
}

-(void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSMutableDictionary *jsError = [NSMutableDictionary dictionaryWithObjectsAndKeys:@1, @"PERMISSION_DENIED", @2, @"POSITION_UNAVAILABLE", @3, @"TIMEOUT", nil];
    
    if (error.code == kCLErrorDenied) {
        jsError[@"code"] = @1;
        jsError[@"message"] = @"User denied Geolocation";
    } else if (error.code == kCLErrorLocationUnknown) {
        jsError[@"code"] = @2;
        jsError[@"message"] = @"Position unavailable";
    }
    
    NSString *js = [LEANUtilities createJsForCallback:@"median_geolocation_failed" data:jsError];
    [self runJavascript:js];
}

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *location = [locations lastObject];
    [self receivedLocation:location];
}

-(void)receivedLocation:(CLLocation*)location {
    NSMutableDictionary *coords = [NSMutableDictionary dictionary];
    coords[@"latitude"] = [NSNumber numberWithDouble:location.coordinate.latitude];
    coords[@"longitude"] = [NSNumber numberWithDouble:location.coordinate.longitude];
    coords[@"accuracy"] = [NSNumber numberWithDouble:location.horizontalAccuracy];
    if (location.verticalAccuracy > 0) {
        coords[@"altitude"] = [NSNumber numberWithDouble:location.altitude];
        coords[@"altitudeAccuracy"] = [NSNumber numberWithDouble:location.verticalAccuracy];
    } else {
        coords[@"altitude"] = [NSNull null];
        coords[@"altitudeAccuracy"] = [NSNull null];
    }
    coords[@"heading"] = location.course < 0 ? [NSNull null] : [NSNumber numberWithDouble:location.course];
    coords[@"speed"] = location.speed < 0 ? [NSNull null] : [NSNumber numberWithDouble:location.speed];
    
    double ts = trunc([[NSDate date] timeIntervalSince1970] * 1000);
    NSNumber *timestamp = [NSNumber numberWithDouble:ts];
    
    NSDictionary *data = @{
                           @"timestamp": timestamp,
                           @"coords": coords
                           };
    
    NSString *js = [LEANUtilities createJsForCallback:@"median_geolocation_received" data:data];
    [self runJavascript:js];
}


#pragma mark - Scroll View Delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    BOOL isScrollable = scrollView.contentSize.height > scrollView.bounds.size.height;
    BOOL isScrolling = scrollView.isTracking && scrollView.isDragging && isScrollable;
    
    CGFloat currentScrollY = scrollView.contentOffset.y;
    CGFloat previousScrollY = self.previousScrollY;
    self.previousScrollY = currentScrollY;
    
    if (!isScrolling || CACurrentMediaTime() < self.nextScrollTime) {
        return;
    }
    self.nextScrollTime = CACurrentMediaTime() + 0.3; // After running animation

    MCKMPNavDefaultStyles *defaultStyles = medianConfig().navDefaultStyles;
    BOOL showNavBar = currentScrollY <= 0 || currentScrollY <= previousScrollY;

    if (self.isShowingTopNavBar && defaultStyles.topNavigationBar.styling.ios.hideOnScroll) {
        [self.navigationController setNavigationBarHidden:!showNavBar animated:YES];
    }

    if (self.tabManager.isShowingTabBar && defaultStyles.bottomTabBar.styling.ios.hideOnScroll) {
        if (showNavBar) {
            [self showTabBarAnimated:YES];
        } else {
            [self hideTabBarAnimated:YES];
        }
    }
}

- (BOOL)prefersStatusBarHidden
{
    return self.isFullscreen || self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    if (self.statusBarStyle) {
        return [self.statusBarStyle integerValue];
    }

    if ([medianConfig().configRoot.styling.iosTheme isEqualToString:@"dark"]) {
        return UIStatusBarStyleLightContent;
    } else {
        return UIStatusBarStyleDefault;
    }
}

-(void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    // usually called because of rotation
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [self adjustInsets];
    [self applyStatusBarOverlay];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        // bar thickness changes when rotating, so resize internal contents
        [self.tabBar invalidateIntrinsicContentSize];
        [self.toolbar invalidateIntrinsicContentSize];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
    }];

    [((LEANAppDelegate *)[UIApplication sharedApplication].delegate).bridge runnerWillTransitionToSizeHost:self width:size.width height:size.height coordinator:(NSObject*)coordinator];
}

- (void)viewWillLayoutSubviews
{
    if (self.statusBarBackground) {
        // fix sizing (usually because of rotation) when navigation bar is hidden
        CGSize statusSize = [UIApplication sharedApplication].currentStatusBarFrame.size;
        CGFloat height = MIN(statusSize.height, statusSize.width);
        // fix for double height status bar on non-iPhoneX
        if (height == 40) {
            height = 20;
        }
        CGFloat width = MAX(statusSize.height, statusSize.width);
        self.statusBarBackground.frame = CGRectMake(0, 0, width, height);
        
        if (self.blurEffectView) {
            self.blurEffectView.frame = CGRectMake(0, 0, width, height);
        }
    }
    [self adjustInsets];
}

-(void)orientationChanged
{
    // fixes status bar weirdness when rotating video to landscape
    [self setNeedsStatusBarAppearanceUpdate];
}

-(void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    // Heights of tab and tool bars will change after rotation, as bars are thinner on landscape.
    // If the bar is hidden, then the bottom constraint is based on the thickness of the bar.
    // The constraint will need to be updated to keep everything in the right place.
    if (self.tabBar.hidden) {
        [self hideBottomBar:self.tabBar constraint:self.tabBarBottomConstraint animated:NO];
    }
    if (self.toolbar.hidden) {
        [self hideBottomBar:self.toolbar constraint:self.toolbarBottomConstraint animated:NO];
    }
    
    // fixes issue on iPhone XS Max and iPhone XR where instrinsic content height = 49
    [self.tabBar invalidateIntrinsicContentSize];
    [self.toolbar invalidateIntrinsicContentSize];

    UIColor *backgroundColor = [UIColor whiteColor];

    // theme and colors
    if ([medianConfig().configRoot.styling.iosTheme isEqualToString:@"dark"]) {
        self.tabBar.barStyle = UIBarStyleBlack;
        self.toolbar.barStyle = UIBarStyleBlack;
        backgroundColor = [UIColor blackColor];
    } else {
        self.tabBar.barStyle = UIBarStyleDefault;
        self.toolbar.barStyle = UIBarStyleDefault;
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            backgroundColor = [UIColor blackColor];
        }
    }
    
    if (![LEANUtilities isGlassDesignEnabled]) {
        self.view.backgroundColor = backgroundColor;
        self.webviewContainer.backgroundColor = backgroundColor;
    }
    
    [self applyStatusBarOverlay];
    
    self.tabBar.barTintColor = [UIColor colorNamed:@"tabBarTintColor"];
}

# pragma theme
-(void)setNativeTheme:(NSString *)mode {
    if (@available(iOS 13.0, *)) {
        if (mode == nil) {
            return;
        }

        if ([medianConfig().configRoot.styling.iosTheme isEqualToString:@"dark"]) {
            mode = @"dark";
        }
        
        if ([mode isEqualToString:@"dark"]) {
            [UIApplication sharedApplication].delegate.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        }
        else if ([mode isEqualToString:@"light"]) {
            [UIApplication sharedApplication].delegate.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        } else {
            [UIApplication sharedApplication].delegate.window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        }
        
        [self updateStatusBarStyle:mode];
    }
}

-(void)setCssTheme:(NSString *)mode andPersistData:(BOOL)persist {
    if (mode == nil) {
        return;
    }

    if ([medianConfig().configRoot.styling.iosTheme isEqualToString:@"dark"]) {
        mode = @"dark";
    }

    [self setCssThemeAttribute:@"data-color-scheme-option" withValue:mode];
    
    if (persist) {
        [[NSUserDefaults standardUserDefaults] setValue:mode forKey:@"darkMode"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

-(void)setCssThemeAttribute:(NSString *)attr withValue:(NSString *)value {
    NSString *js = [NSString stringWithFormat:@"document.documentElement.setAttribute(\"%@\", \"%@\");", attr, value];
    [self.wkWebview evaluateJavaScript:js completionHandler:nil];
}

- (void)updateStatusBarBackgroundColor:(UIColor *)backgroundColor enableBlurEffect:(BOOL)isBlurEnabled{
    if (!backgroundColor) return;

    UIView *background = [[UIView alloc] init];
    background.backgroundColor = backgroundColor;
    [self.statusBarBackground removeFromSuperview];
    self.statusBarBackground = background;
    [self.view addSubview:self.statusBarBackground];
    
    if (isBlurEnabled) {
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
        [self.blurEffectView removeFromSuperview];
        self.blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        [self.view addSubview:self.blurEffectView];
    }
}

- (void)updateStatusBarOverlay:(BOOL)isOverlayEnabled{
    self.statusBarOverlay = isOverlayEnabled;
    [self applyStatusBarOverlay];
}

- (void)updateStatusBarStyle:(NSString *)statusBarStyle{
    if ([statusBarStyle isEqualToString:@"light"]) {
        // dark icons and text
        if (@available(iOS 13.0, *)) {
            self.statusBarStyle = [NSNumber numberWithInteger:UIStatusBarStyleDarkContent];
        } else {
            self.statusBarStyle = [NSNumber numberWithInteger:UIStatusBarStyleDefault];
        }
    } else if ([statusBarStyle isEqualToString:@"dark"]) {
        // light icons and text
        self.statusBarStyle = [NSNumber numberWithInteger:UIStatusBarStyleLightContent];
    } else {
        self.statusBarStyle = [NSNumber numberWithInteger:UIStatusBarStyleDefault];
    }
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)updateViewBackgroundColor {
    if ([LEANUtilities isGlassDesignEnabled] && MCKMPMutableConfig.shared.instance.configRoot.general.injectMedianJS) {
        [LEANUtilities getBodyBackgroundColor:self.wkWebview completion:^(UIColor *color) {
            self.view.backgroundColor = color;
            self.webviewContainer.backgroundColor = color;
        }];
    }
}

#pragma mark - MCKMPIOSAppHost

// WebView / VC -------------------------------------------------------------

- (WKWebView *)getWebView {
    return self.wkWebview;
}

- (void)runJavascriptScript:(NSString *)script {
    [self runJavascript:script];
}

- (void)loadUrlUrl:(NSString *)url {
    [self loadUrlString:url];
}

- (void)loadUrlUrl_:(NSURL *)url {
    [self loadUrl:url];
}

- (UIViewController *)getViewController {
    return self;
}

- (void)presentViewControllerViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [[self getTopPresentedViewController] presentViewController:viewController animated:animated completion:nil];
}

- (void)dismissViewControllerAnimated:(BOOL)animated {
    [self dismissViewControllerAnimated:animated completion:nil];
}

// Navigation / tabs / sidebar ----------------------------------------------

- (void)selectTabTabNumber:(int32_t)tabNumber {
    [self.tabManager selectTabNumber:tabNumber];
}

- (void)deselectTabs {
    [self.tabManager deselectTabs];
}

- (void)setTabsTabsJson:(NSString *)tabsJson {
    id tabs = [NSJSONSerialization JSONObjectWithData:[tabsJson dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if ([tabs isKindOfClass:[NSDictionary class]]) {
        [self.tabManager setTabsWithJson:tabs];
        self.tabManager.javascriptTabs = YES;
    }
}

- (int32_t)getUrlLevel {
    return (int32_t)self.urlLevel;
}

- (void)setUrlLevelUrlLevel:(int32_t)urlLevel {
    self.urlLevel = urlLevel;
}

- (int32_t)urlLevelForUrlUrl:(NSString *)url {
    return (int32_t)[LEANWebViewController urlLevelForUrl:[NSURL URLWithString:url]];
}

- (NSString *)titleForUrlUrl:(NSString *)url {
    return [LEANWebViewController titleForUrl:[NSURL URLWithString:url]] ?: @"";
}

- (void)closeCurrentWindow {
    if (self.navigationController.viewControllers.count > 1) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
    }
}

- (void)openNewWindowUrl:(NSString *)url mode:(NSString *)mode {
    [self.windowsManager openUrl:[NSURL URLWithString:url] mode:mode];
}

- (void)checkNavigationForPageUrl:(NSString *)url {
    [self checkNavigationForUrl:[NSURL URLWithString:url]];
}

- (void)checkPreNavigationForPageUrl:(NSString *)url {
    [self checkPreNavigationForUrl:[NSURL URLWithString:url]];
}

- (void)updateMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        [(LEANMenuViewController*)self.frostedViewController.menuViewController updateMenuWithStatus:@"default"];
    });
}

- (void)setSidebarNavigationEnabledEnabled:(BOOL)enabled {
    // nav2: median-core keeps the JS flag across pages and re-renders through applyNav2ForUrl:
    if (medianConfig().isNativeNavigationV2) {
        [medianConfig() setNavSidebarEnabledEnabled:enabled];
        return;
    }
    [self setSidebarEnabled:enabled];
}

- (void)setSidebarItemsItemsJson:(NSString *)itemsJson enabled:(BOOL)enabled persist:(BOOL)persist {
    [medianConfig() setSidebarMenusFromJsonItemsJson:itemsJson showNavigationMenu:enabled persist:persist];
    if (medianConfig().isNativeNavigationV2) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setSidebarEnabled:enabled];
        self.navigationItem.titleView = self.defaultTitleView;
        [self updateNavigationBarItemsAnimated:NO];
    });
}

// median.sidebar.getItems: replies {"default": [...]} with the sidebar for this page, as V1 did
- (void)getSidebarItemsCallback:(NSString *)callback {
    NSString *json = [medianConfig() sidebarMenusJsonForUrlUrl:self.wkWebview.URL.absoluteString ?: @""];
    NSDictionary *menus = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![menus isKindOfClass:[NSDictionary class]]) return;
    [self runJavascriptWithCallback:callback data:menus];
}

- (void)setNavigationLevelsData:(NSDictionary<NSString *,id> * _Nullable)data persist:(BOOL)persist {
    [medianConfig() setNavigationLevelsRawData:data persist:persist];
}

- (void)setNavigationTitlesData:(NSDictionary<NSString *,id> * _Nullable)data persist:(BOOL)persist {
    [medianConfig() setNavigationTitlesRawData:data persist:persist];
}

- (void)setMaxWindowsEnabled:(BOOL)enabled numWindows:(int32_t)numWindows autoClose:(BOOL)autoClose persist:(BOOL)persist {
    [medianConfig() setMaxWindowsEnabled:enabled numWindows:numWindows autoClose:autoClose persist:persist];
    [self updateWindowsController];
}

- (void)setWindowOpenHideNavbarHide:(BOOL)hide {
    [LEANWebViewController setWindowOpenHideNavbar:hide];
}

- (void)setInternalExternalRulesRulesJson:(NSString *)rulesJson {
    [medianConfig() setRegexRulesFromJsonRulesJson:rulesJson];
}

- (void)setInitialUrlUrl:(NSString *)url {
    [self.configPreferences setInitialUrl:url];
}

// Appearance ----------------------------------------------------------------

- (void)setCustomTitleTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.navigationItem.title = title.length > 0 ? title : medianConfig().configRoot.general.appName;
        // hide titleView
        self.defaultTitleView = nil;
        self.navigationItem.titleView = nil;
    });
}

- (void)toggleFullscreenFullscreen:(BOOL)fullscreen {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isFullscreen = fullscreen;
        [self.navigationController setNavigationBarHidden:fullscreen animated:YES];
        if (fullscreen) {
            [self hideToolbarAnimated:YES];
            [self hideTabBarAnimated:YES];
        } else {
            [self checkNavigationForUrl:self.wkWebview.URL]; // restore tab/toolbar per config
        }
        [self setNeedsStatusBarAppearanceUpdate];
        [self adjustInsets];
    });
}

- (void)setBrightnessBrightness:(float)brightness {
    if (brightness < 0) {
        // restore default
        if (self.savedScreenBrightness >= 0) {
            [UIScreen mainScreen].brightness = self.savedScreenBrightness;
        }
        self.restoreBrightnessOnNavigation = NO;
        return;
    }
    if (brightness > 1.0) return;
    self.savedScreenBrightness = [UIScreen mainScreen].brightness;
    [UIScreen mainScreen].brightness = brightness;
}

- (void)setRestoreBrightnessOnNavigationRestore:(BOOL)restore {
    self.restoreBrightnessOnNavigation = restore;
}

- (void)setZoomScale:(double)scale {
    [self.viewportManager setViewportWithScale:@(scale) width:nil webView:self.wkWebview];
    [medianConfig() setWebviewZoomZoom:(float)scale];
}

- (double)getZoom {
    NSNumber *zoom = medianConfig().webviewZoom;
    return zoom ? zoom.doubleValue : 1.0;
}

- (void)setNativeThemeMode:(NSString *)mode {
    [self setNativeTheme:mode];
}

- (void)setCssThemeMode:(NSString *)mode persist:(BOOL)persist {
    [self setCssTheme:mode andPersistData:persist];
}

- (void)resetAppTheme {
    NSString *defaultMode = medianConfig().configRoot.styling.iosDarkMode;
    [self setNativeTheme:defaultMode];
    [self setCssTheme:defaultMode andPersistData:YES];
}

- (void)updateStatusBarStyleStyle:(NSString *)style {
    [self updateStatusBarStyle:style];
}

- (void)setStatusBarColorColor:(NSString *)color blur:(BOOL)blur {
    [self updateStatusBarBackgroundColor:[LEANUtilities colorWithAlphaFromHexString:color] enableBlurEffect:blur];
}

- (void)updateStatusBarOverlayIsOverlayEnabled:(BOOL)isOverlayEnabled {
    [self updateStatusBarOverlay:isOverlayEnabled];
}

- (void)matchStatusBarToBodyBackgroundColorEnabled:(BOOL)enabled {
    [LEANUtilities matchStatusBarToBodyBackgroundColor:self.wkWebview enabled:enabled];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"matchStatusBarToBodyBgColor"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setNavigationBarHiddenHidden:(BOOL)hidden animated:(BOOL)animated {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.navigationController setNavigationBarHidden:hidden animated:animated];
    });
}

- (void)setToolbarHiddenHidden:(BOOL)hidden animated:(BOOL)animated {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (hidden) {
            [self hideToolbarAnimated:animated];
        } else {
            [self showToolbarAnimated:animated];
        }
    });
}

// Share / download -----------------------------------------------------------

- (void)sharePageUrl:(NSString *)url text:(NSString *)text {
    [self sharePageWithUrl:url.length > 0 ? url : nil text:text.length > 0 ? text : nil sender:nil];
}

- (void)downloadFileUrl:(NSString *)url filename:(NSString *)filename shouldSaveToGallery:(BOOL)shouldSaveToGallery open:(BOOL)open callback:(NSString *)callback {
    NSURL *downloadUrl = [NSURL URLWithString:url relativeToURL:self.currentRequest.URL];
    if (!downloadUrl) return;

    if (shouldSaveToGallery) {
        [self.documentSharer downloadImage:downloadUrl completion:^(NSDictionary *result) {
            [self runJavascriptWithCallback:callback data:result];
        }];
        return;
    }

    if ([downloadUrl.scheme isEqualToString:@"blob"]) {
        [self.fileWriterSharer downloadBlobUrl:downloadUrl filename:filename callback:callback];
        return;
    }

    [self.documentSharer shareUrl:downloadUrl fromView:self.wkWebview filename:filename open:open completion:^(NSString *error) {
        if (error) {
            [self runJavascriptWithCallback:callback data:@{ @"success": @NO, @"error": error }];
        } else {
            [self runJavascriptWithCallback:callback data:@{ @"success": @YES }];
        }
    }];
}

// Device / connectivity / location / clipboard ------------------------------

- (void)runGonativeDeviceInfoCallback:(NSString *)callback includeCarrierNames:(BOOL)includeCarrierNames {
    [self runGonativeDeviceInfoWithCallback:callback];
}

- (NSDictionary<NSString *,id> *)getDeviceInfo {
    MCKMPDeviceInfo *info = [[[MCKMPIOSDeviceInfoProvider alloc] initWithBundle:NSBundle.mainBundle] getDeviceInfo];
    NSMutableDictionary *result = [[info toMap] mutableCopy];

    LEANAppDelegate *appDelegate = (LEANAppDelegate*)[UIApplication sharedApplication].delegate;
    if (appDelegate.apnsToken) result[@"apnsToken"] = appDelegate.apnsToken;
    result[@"isFirstLaunch"] = @(appDelegate.isFirstLaunch);
    NSString *publicKey = medianConfig().configRoot.general.publicKey;
    result[@"publicKey"] = publicKey ?: @"";

    return result;
}

- (void)sendConnectivityOnceCallback:(NSString *)callback {
    [self runJavascriptWithCallback:callback data:[self getConnectivity]];
}

- (void)subscribeConnectivityCallback:(NSString *)callback {
    [self runJavascriptWithCallback:callback data:[self getConnectivity]];
    self.connectivityCallback = callback;
}

- (void)unsubscribeConnectivity {
    self.connectivityCallback = nil;
}

- (void)promptLocationService {
    [self requestLocation];
}

- (void)clipboardSetContent:(NSString *)content {
    if (content && ![content isEqual:[NSNull null]]) {
        [[UIPasteboard generalPasteboard] setString:content];
    }
}

- (void)clipboardGetCallback:(NSString *)callback {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSDictionary *dict;
    if (pasteboard && [pasteboard hasStrings]) {
        dict = @{@"data": [pasteboard string]};
    } else {
        dict = @{@"error": @"Clipboard item is not a string."};
    }
    [self runJavascriptWithCallback:callback data:dict];
}

// Keyboard --------------------------------------------------------------------

- (void)getKeyboardInfoCallback:(NSString *)callback {
    [self runKeyboardInfoWithCallback:callback];
}

- (void)addKeyboardListenerCallback:(NSString *)callback {
    self.keyboardListenerCallback = callback;
}

- (void)showKeyboardAccessoryViewVisible:(BOOL)visible {
    [self.keyboardManager showKeyboardAccessoryView:visible];
}

// Events ----------------------------------------------------------------------

- (void)invokeCallbackEventName:(NSString *)eventName data:(NSDictionary<NSString *,id> *)data {
    [self triggerEvent:eventName data:data];
}

- (void)subscribeEventEventName:(NSString *)eventName {
    [self.eventsManager subscribeEvent:eventName];
}

- (void)unsubscribeEventEventName:(NSString *)eventName {
    [self.eventsManager unsubscribeEvent:eventName];
}

// Context menu / permissions ----------------------------------------------------

- (void)setContextMenuEnabledEnabled:(BOOL)enabled {
    [ContextMenuHandler setEnabled:enabled];
}

- (void)setContextMenuLinkActionsConfig:(NSDictionary<NSString *,id> *)config {
    id actions = config[@"actions"];
    if ([actions isKindOfClass:[NSArray class]]) {
        [ContextMenuHandler setLinkActions:actions];
    }
}

- (NSDictionary<NSString *,NSString *> *)checkPermissionStatusPermissions:(NSArray<NSString *> *)permissions {
    return [MedianPermissionHandler getStatusWithKeys:permissions];
}

// Misc ----------------------------------------------------------------------------

- (void)sendRegistrationData:(NSDictionary<NSString *,id> *)data {
    // registration service dropped (legacy)
}

- (void)runCustomNativeBridgeParams:(NSDictionary<NSString *,NSString *> *)params {
    [self runCustomCode:params];
}

- (void)handleContextualNavToolbarPath:(NSString *)path params:(NSDictionary<NSString *,id> *)params {
    NSURL *url = [NSURL URLWithString:[@"median://ios" stringByAppendingString:path]];
    if (url) [self.toolbarManager handleUrl:url query:params];
}

- (void)setWebConsoleLogsEnabledEnabled:(BOOL)enabled {
    self.logManager = [[GNLogManager alloc] initWithWebview:self.wkWebview enabled:enabled];
}

- (void)getWebConsoleLogsCallback:(NSString *)callback {
    // legacy GNLogManager only relayed /print; nothing buffered to return
    [self runJavascriptWithCallback:callback data:@{@"logs": @[]}];
}

@end
