
// OneKeepAlive.m
// Robust background keep-alive that ONLY runs in background, never in foreground.
// Stops immediately on foreground, route changes, interruptions, or when other audio is active.

@import Foundation;
@import UIKit;
@import AVFoundation;
@import AudioToolbox;

static NSString * const kOKALogTag = @"[OneKeepAlive]";

// Simple logger (disabled in release if needed)
static inline void OKALog(NSString *fmt, ...) {
#ifdef DEBUG
    va_list args; va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    fprintf(stderr, "%s %s\n", kOKALogTag.UTF8String, s.UTF8String);
#endif
}

// Minimal silent generator using AVAudioEngine (no bundled assets needed)
@interface OKASilencer : NSObject
@property(nonatomic,strong) AVAudioEngine *engine;
@property(nonatomic,strong) AVAudioPlayerNode *node;
@property(nonatomic,strong) AVAudioPCMBuffer *silence;
@property(nonatomic,assign) BOOL running;
- (void)start;
- (void)stop;
@end

@implementation OKASilencer
- (instancetype)init {
    if ((self = [super init])) {
        _engine = [AVAudioEngine new];
        _node   = [AVAudioPlayerNode new];
        AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
        _silence = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt frameCapacity:4410]; // 0.1s
        _silence.frameLength = 4410;
        memset(_silence.floatChannelData[0], 0, _silence.frameLength * sizeof(float));
        memset(_silence.floatChannelData[1], 0, _silence.frameLength * sizeof(float));
        [_engine attachNode:_node];
        [_engine connect:_node to:_engine.mainMixerNode format:fmt];
    }
    return self;
}
- (void)start {
    if (_running) return;
    NSError *err = nil;
    if (![_engine isRunning]) {
        [_engine startAndReturnError:&err];
        if (err) { OKALog(@"engine start error: %@", err); }
    }
    if (![_node isPlaying]) {
        [_node play];
        // schedule continuous silence
        __block __weak AVAudioPlayerNode *weakNode = _node;
        __block __weak AVAudioPCMBuffer *weakBuf = _silence;
        [_node scheduleBuffer:_silence atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:^{
            // No-op, loops automatically
            (void)weakNode; (void)weakBuf;
        }];
    }
    _running = YES;
    OKALog(@"silencer started");
}
- (void)stop {
    if (!_running) return;
    @try { [_node stop]; } @catch(__unused NSException *ex) {}
    if ([_engine isRunning]) { [_engine stop]; }
    _running = NO;
    OKALog(@"silencer stopped");
}
@end

@interface OKAKeepAlive : NSObject
@property(nonatomic,strong) OKASilencer *silencer;
@property(nonatomic,assign) UIBackgroundTaskIdentifier bgTask;
@end

@implementation OKAKeepAlive

+ (instancetype)shared {
    static OKAKeepAlive *S; static dispatch_once_t once; dispatch_once(&once, ^{ S = [OKAKeepAlive new]; });
    return S;
}

- (instancetype)init {
    if ((self = [super init])) {
        _silencer = [OKASilencer new];
        _bgTask = UIBackgroundTaskInvalid;

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
        [nc addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
        [nc addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];

        // If we’re injected while already running, align state
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIApplicationState st = UIApplication.sharedApplication.applicationState;
            if (st == UIApplicationStateBackground) {
                [self appDidEnterBackground:nil];
            } else {
                [self appWillEnterForeground:nil];
            }
        });
    }
    return self;
}

#pragma mark - Helpers

- (BOOL)otherAudioActive {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    return s.isOtherAudioPlaying;
}

- (void)configureSessionForBackground {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSError *err = nil;
    AVAudioSessionCategoryOptions opts = AVAudioSessionCategoryOptionMixWithOthers
                                       | AVAudioSessionCategoryOptionAllowBluetooth
                                       | AVAudioSessionCategoryOptionAllowBluetoothA2DP
                                       | AVAudioSessionCategoryOptionAllowAirPlay;
    BOOL ok = [s setCategory:AVAudioSessionCategoryPlayback withOptions:opts error:&err];
    if (!ok || err) { OKALog(@"setCategory(playback) err=%@", err); }
    ok = [s setActive:YES error:&err];
    if (!ok || err) { OKALog(@"setActive YES err=%@", err); }
}

- (void)configureSessionForForegroundIdle {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSError *err = nil;
    BOOL ok = [s setCategory:AVAudioSessionCategoryAmbient error:&err];
    if (!ok || err) { OKALog(@"setCategory(ambient) err=%@", err); }
    ok = [s setActive:NO error:&err]; // yield to recorder/players
    if (!ok && err.code != AVAudioSessionErrorCodeIsBusy) {
        OKALog(@"setActive NO err=%@", err);
    }
}

- (void)beginBGTaskIfNeeded {
    if (_bgTask != UIBackgroundTaskInvalid) return;
    _bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"OneKeepAlive" expirationHandler:^{
        [self endBGTask];
    }];
}

- (void)endBGTask {
    if (_bgTask == UIBackgroundTaskInvalid) return;
    [UIApplication.sharedApplication endBackgroundTask:_bgTask];
    _bgTask = UIBackgroundTaskInvalid;
}

#pragma mark - Notifications

- (void)appDidEnterBackground:(NSNotification *)n {
    // Only keep alive when in background AND no other audio is active (avoid conflicts)
    if ([self otherAudioActive]) {
        OKALog(@"other audio active -> not starting silencer");
        return;
    }
    [self configureSessionForBackground];
    [_silencer start];
    [self beginBGTaskIfNeeded];
    OKALog(@"entered background -> keep-alive ON");
}

- (void)appWillEnterForeground:(NSNotification *)n {
    [_silencer stop];
    [self configureSessionForForegroundIdle];
    [self endBGTask];
    OKALog(@"entering foreground -> keep-alive OFF");
}

- (void)audioInterrupted:(NSNotification *)n {
    NSDictionary *i = n.userInfo ?: @{};
    NSInteger type = [i[AVAudioSessionInterruptionTypeKey] integerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        OKALog(@"interruption began -> stop");
        [_silencer stop];
    } else {
        OKALog(@"interruption ended");
        // If still background and no other audio, resume
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground && ![self otherAudioActive]) {
            [self configureSessionForBackground];
            [_silencer start];
        }
    }
}

- (void)routeChanged:(NSNotification *)n {
    NSNumber *reason = n.userInfo[AVAudioSessionRouteChangeReasonKey];
    if (reason.integerValue == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ||
        reason.integerValue == AVAudioSessionRouteChangeReasonNewDeviceAvailable) {
        // Re-check policy
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground && ![self otherAudioActive]) {
            [self configureSessionForBackground];
            if (!_silencer.running) [_silencer start];
        } else {
            [_silencer stop];
            [self configureSessionForForegroundIdle];
        }
    }
}

@end

__attribute__((constructor))
static void OKAInit(void) {
    @autoreleasepool {
        (void)[OKAKeepAlive shared];
        OKALog(@"constructor fired");
    }
}
