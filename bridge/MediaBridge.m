// Notchly media bridge: reads system-wide "Now Playing" via MediaRemote.
// Loaded into /usr/bin/perl (Apple-signed) so the private framework answers us.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>

typedef void (^NPInfoBlock)(CFDictionaryRef info);
typedef void (^NPBoolBlock)(Boolean b);
typedef void (^NPStrBlock)(CFStringRef s);
typedef void (*NPGetInfo)(dispatch_queue_t, NPInfoBlock);
typedef void (*NPGetPlaying)(dispatch_queue_t, NPBoolBlock);
typedef void (*NPGetApp)(dispatch_queue_t, NPStrBlock);
typedef Boolean (*NPSend)(uint32_t, CFDictionaryRef);
typedef void (*NPSetElapsed)(double);

static void *mr(void) {
    static void *h = NULL;
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    return h;
}

static NSString *lastKey = @"";
static BOOL artSent = NO;

static double num(id v) {
    if (![v isKindOfClass:[NSNumber class]]) return 0;
    double d = [v doubleValue];
    return isfinite(d) ? d : 0;
}

static void emit(NSDictionary *d, BOOL playing, NSString *app) {
    @autoreleasepool {
        NSString *title = d[@"kMRMediaRemoteNowPlayingInfoTitle"];
        NSString *artist = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSString *album = d[@"kMRMediaRemoteNowPlayingInfoAlbum"];
        if (![title isKindOfClass:[NSString class]]) title = @"";
        if (![artist isKindOfClass:[NSString class]]) artist = @"";
        if (![album isKindOfClass:[NSString class]]) album = @"";
        double dur = num(d[@"kMRMediaRemoteNowPlayingInfoDuration"]);
        double el = num(d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
        id ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if (playing && [ts isKindOfClass:[NSDate class]]) el += [[NSDate date] timeIntervalSinceDate:ts];
        if (dur > 0 && el > dur) el = dur;
        NSMutableDictionary *o = [NSMutableDictionary dictionary];
        o[@"title"] = title; o[@"artist"] = artist; o[@"album"] = album;
        o[@"duration"] = @(dur); o[@"elapsed"] = @(el < 0 ? 0 : el);
        o[@"playing"] = @(playing);
        o[@"app"] = ([app isKindOfClass:[NSString class]] ? app : @"");
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@", title, artist, album];
        if (![key isEqualToString:lastKey]) { lastKey = key; artSent = NO; }
        id art = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if (!artSent && [art isKindOfClass:[NSData class]] && [art length] > 0) {
            o[@"art"] = [art base64EncodedStringWithOptions:0];
            artSent = YES;
        }
        NSData *j = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
        if (!j) return;
        fwrite([j bytes], 1, [j length], stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
}

static dispatch_source_t timerSrc;

void notchly_media_stream(void *a, void *b) {
    if (!mr()) return;
    NPGetInfo getInfo = (NPGetInfo)dlsym(mr(), "MRMediaRemoteGetNowPlayingInfo");
    NPGetPlaying getPlaying = (NPGetPlaying)dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    NPGetApp getApp = (NPGetApp)dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationDisplayID");
    if (!getInfo || !getPlaying || !getApp) return;
    dispatch_queue_t q = dispatch_queue_create("notchly.mr", DISPATCH_QUEUE_SERIAL);
    timerSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(timerSrc, DISPATCH_TIME_NOW, (uint64_t)(0.5 * NSEC_PER_SEC), (uint64_t)(0.1 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timerSrc, ^{
        getInfo(q, ^(CFDictionaryRef info) {
            NSDictionary *d = info ? [(__bridge NSDictionary *)info copy] : @{};
            getPlaying(q, ^(Boolean playing) {
                getApp(q, ^(CFStringRef app) {
                    emit(d, playing, app ? (__bridge NSString *)app : @"");
                });
            });
        });
    });
    dispatch_resume(timerSrc);
    dispatch_semaphore_wait(dispatch_semaphore_create(0), DISPATCH_TIME_FOREVER);
}

void notchly_media_send(void *a, void *b) {
    const char *c = getenv("NOTCHLY_CMD");
    if (!c || !mr()) return;
    int cmd = atoi(c);
    if (cmd == 100) {
        NPSetElapsed f = (NPSetElapsed)dlsym(mr(), "MRMediaRemoteSetElapsedTime");
        const char *s = getenv("NOTCHLY_SEEK");
        if (f && s) f(atof(s));
    } else {
        NPSend f = (NPSend)dlsym(mr(), "MRMediaRemoteSendCommand");
        if (f) f((uint32_t)cmd, NULL);
    }
    usleep(250000);
}
