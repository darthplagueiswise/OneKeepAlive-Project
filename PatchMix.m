// PatchMix.m
@import Foundation;
@import UIKit;
@import AVFoundation;
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL oka_isForeground(void) {
    UIApplication *app = [UIApplication sharedApplication];
    return app.applicationState == UIApplicationStateActive;
}

static AVAudioSessionCategoryOptions oka_withMix(AVAudioSessionCategoryOptions opts) {
    return (opts | AVAudioSessionCategoryOptionMixWithOthers);
}

static NSString *oka_foregroundCategory(NSString *original) {
    // Foreground: Ambient + MixWithOthers
    return AVAudioSessionCategoryAmbient;
}

static NSString *oka_backgroundCategory(NSString *original) {
    // Background: keep original (e.g., Playback), only ensure MixWithOthers
    return original ?: AVAudioSessionCategoryPlayback;
}

// iOS 10+: -setCategory:withOptions:error:
typedef BOOL (*SetCatOptErrIMP)(id, SEL, NSString*, AVAudioSessionCategoryOptions, NSError**);
// iOS older: -setCategory:error:
typedef BOOL (*SetCatErrIMP)(id, SEL, NSString*, NSError**);

static IMP g_orig_setCatOptErr = NULL;
static IMP g_orig_setCatErr    = NULL;

static BOOL oka_setCategory_options_error(id self, SEL _cmd,
                                          NSString *category,
                                          AVAudioSessionCategoryOptions options,
                                          NSError **error)
{
    NSString *cat = oka_isForeground() ? oka_foregroundCategory(category)
                                       : oka_backgroundCategory(category);
    AVAudioSessionCategoryOptions opts = oka_withMix(options);

    SetCatOptErrIMP orig = (SetCatOptErrIMP)g_orig_setCatOptErr;
    if (!orig) {
        orig = (SetCatOptErrIMP)[[AVAudioSession class] instanceMethodForSelector:_cmd];
    }
    return orig(self, _cmd, cat, opts, error);
}

static BOOL oka_setCategory_error(id self, SEL _cmd,
                                  NSString *category, NSError **error)
{
    NSString *cat = oka_isForeground() ? oka_foregroundCategory(category)
                                       : oka_backgroundCategory(category);
    SetCatErrIMP orig = (SetCatErrIMP)g_orig_setCatErr;
    if (!orig) {
        orig = (SetCatErrIMP)[[AVAudioSession class] instanceMethodForSelector:_cmd];
    }
    BOOL ok = orig(self, _cmd, cat, error);
    if (ok) {
        AVAudioSession *s = (AVAudioSession *)self;
        [s setActive:NO error:nil];
        if ([s respondsToSelector:@selector(setCategory:withOptions:error:)]) {
            [s setCategory:cat withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        }
        [s setActive:YES error:nil];
    }
    return ok;
}

static void oka_applyForCurrentState(void) {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSString *current = s.category;
    NSError *err = nil;

    if (oka_isForeground()) {
        [s setActive:NO error:&err];
        [s setCategory:AVAudioSessionCategoryAmbient
            withOptions:AVAudioSessionCategoryOptionMixWithOthers
                  error:&err];
        [s setActive:YES error:&err];
    } else {
        [s setActive:NO error:&err];
        if ([s respondsToSelector:@selector(setCategory:withOptions:error:)]) {
            [s setCategory:(current ?: AVAudioSessionCategoryPlayback)
                withOptions:AVAudioSessionCategoryOptionMixWithOthers
                      error:&err];
        } else {
            [s setCategory:(current ?: AVAudioSessionCategoryPlayback) error:&err];
            [s setCategory:(current ?: AVAudioSessionCategoryPlayback)
                withOptions:AVAudioSessionCategoryOptionMixWithOthers
                      error:&err];
        }
        [s setActive:YES error:&err];
    }
}

static void oka_swizzle_method(Class cls, SEL sel, IMP repl, IMP *storeOrig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        IMP old = method_getImplementation(m);
        if (storeOrig) *storeOrig = old;
        method_setImplementation(m, repl);
    } else {
        // If method not found, just add ours (best effort).
        class_addMethod(cls, sel, repl, "c@:@@^@");
    }
}

__attribute__((constructor))
static void oka_patch_init(void) {
    Class cls = [AVAudioSession class];

    // swizzle -setCategory:withOptions:error:
    SEL sel1 = @selector(setCategory:withOptions:error:);
    oka_swizzle_method(cls, sel1, (IMP)oka_setCategory_options_error, &g_orig_setCatOptErr);

    // swizzle -setCategory:error:
    SEL sel2 = @selector(setCategory:error:);
    oka_swizzle_method(cls, sel2, (IMP)oka_setCategory_error, &g_orig_setCatErr);

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification * _Nonnull n) {
        oka_applyForCurrentState();
    }];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification * _Nonnull n) {
        oka_applyForCurrentState();
    }];
    [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification * _Nonnull n) {
        oka_applyForCurrentState();
    }];
    [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification * _Nonnull n) {
        oka_applyForCurrentState();
    }];

    dispatch_async(dispatch_get_main_queue(), ^{
        oka_applyForCurrentState();
    });
}