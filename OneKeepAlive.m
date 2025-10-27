//
//  OneKeepAlive.m
//  Única dylib para substituir ICEnabled + Notifications2
//
//  Estratégia:
//  - Em BACKGROUND: AVAudioSessionCategoryPlayback | .mixWithOthers (mantém keep-alive sem matar outros apps)
//  - Em FOREGROUND: AVAudioSessionCategoryAmbient | .mixWithOthers (não segura o mic, evita cortes)
//  - Quando detectar gravação (PlayAndRecord / rota de entrada ativa): libera total (setActive:NO) e reconfigura
//  - Swizzle setCategory:/setActive: para garantir ordem "categoria+opções -> setActive"
//  - Observa interrupções/rota/background/foreground para re-aplicar política com estabilidade
//
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifndef OKA_LOG
#define OKA_LOG 0
#endif
#define OKALog(fmt, ...) do { if (OKA_LOG) NSLog(@"[OneKeepAlive] " fmt, ##__VA_ARGS__); } while(0)

static BOOL oka_isRecording(void) {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    if ([s.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) return YES;
    AVAudioSessionRouteDescription *route = s.currentRoute;
    for (AVAudioSessionPortDescription *inPort in route.inputs) {
        if ([inPort.portType isEqualToString:AVAudioSessionPortBuiltInMic] ||
            [inPort.portType isEqualToString:AVAudioSessionPortHeadsetMic] ||
            [inPort.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
            return YES;
        }
    }
    return NO;
}

static void oka_applyForeground(void) {
    NSError *err = nil;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    if (oka_isRecording()) {
        // durante gravação, solta a sessão para evitar disputa
        [s setActive:NO error:&err];
        err = nil;
        [s setCategory:AVAudioSessionCategoryAmbient error:&err];
        OKALog(@"FG+REC: Ambient + inactive (%@)", err);
    } else {
        err = nil;
        [s setCategory:AVAudioSessionCategoryAmbient
            withOptions:AVAudioSessionCategoryOptionMixWithOthers
                  error:&err];
        OKALog(@"FG: Ambient+Mix (%@)", err);
        err = nil;
        [s setActive:YES error:&err];
    }
}

static void oka_applyBackground(void) {
    NSError *err = nil;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback
        withOptions:AVAudioSessionCategoryOptionMixWithOthers
              error:&err];
    OKALog(@"BG: Playback+Mix (%@)", err);
    err = nil;
    [s setActive:YES error:&err];
}

static void oka_reapplyByAppState(void) {
    UIApplicationState st = UIApplication.sharedApplication.applicationState;
    if (st == UIApplicationStateBackground || st == UIApplicationStateInactive) {
        oka_applyBackground();
    } else {
        oka_applyForeground();
    }
}

static void oka_swizzle(Class c, SEL orig, SEL repl) {
    Method m1 = class_getInstanceMethod(c, orig);
    Method m2 = class_getInstanceMethod(c, repl);
    if (!m1 || !m2) return;
    method_exchangeImplementations(m1, m2);
}

// Swizzled declarations
@interface AVAudioSession (OKA)
- (BOOL)oka_setActive:(BOOL)active error:(NSError **)outError;
- (BOOL)oka_setCategory:(NSString *)category error:(NSError **)outError;
- (BOOL)oka_setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError;
@end

@implementation AVAudioSession (OKA)

- (BOOL)oka_setActive:(BOOL)active error:(NSError **)outError {
    // Antes de cada ativação, garanta política certa para o estado atual
    oka_reapplyByAppState();
    return [self oka_setActive:active error:outError];
}

- (BOOL)oka_setCategory:(NSString *)category error:(NSError **)outError {
    if ([category isEqualToString:AVAudioSessionCategoryPlayback]) {
        return [self oka_setCategory:category withOptions:AVAudioSessionCategoryOptionMixWithOthers error:outError];
    }
    return [self oka_setCategory:category error:outError];
}

- (BOOL)oka_setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if ([category isEqualToString:AVAudioSessionCategoryPlayback]) {
        options |= AVAudioSessionCategoryOptionMixWithOthers;
        options &= ~AVAudioSessionCategoryOptionDuckOthers;
    }
    return [self oka_setCategory:category withOptions:options error:outError];
}

@end

__attribute__((constructor))
static void oka_init(void) {
    @autoreleasepool {
        Class cls = [AVAudioSession class];
        oka_swizzle(cls, @selector(setActive:error:), @selector(oka_setActive:error:));
        oka_swizzle(cls, @selector(setCategory:error:), @selector(oka_setCategory:error:));
        oka_swizzle(cls, @selector(setCategory:withOptions:error:), @selector(oka_setCategory:withOptions:error:));

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification * n) {
            oka_applyBackground();
        }];
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification * n) {
            oka_applyForeground();
        }];
        [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil usingBlock:^(__unused NSNotification * n) {
            oka_reapplyByAppState();
        }];
        [nc addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification * n) {
            // Se o usuário plugou/desplugou fone/mic, reavalia categoria
            oka_reapplyByAppState();
        }];
    }
}
