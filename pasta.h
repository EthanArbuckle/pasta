#include <substrate.h>
#import <QuartzCore/CAFilter.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);

#ifdef __cplusplus
}
#endif

#define springToBackPortName CFSTR("gucci.sb2bbChannel")
#define backToSpringPortName CFSTR("gucci.bb2sbChannel")


enum {
    springboardServerToBackboardRemote,
    backboardRemoteToSpringboardServer
};

CFDataRef receiveSpringBoardImage(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info);
CFDataRef shouldResumePrettyRespring(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info);

@interface sb_to_bb_snapshot_provider : NSObject
@property (nonatomic, retain) NSData *sbSnapshotData;
@property (nonatomic) BOOL prettyRespringQueued;
@property (nonatomic) BOOL recoveringFromPrettyRespring;
+ (id)sharedInstance;
- (UIImage *)getSpringboardImage;
- (void)setSpringboardImage:(NSData *)data;
@end

//from backboardd
@interface BKSystemApplication : NSObject
- (NSString *)bundleIdentifier;
@end

//from springboard
@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
- (void)unlockUIFromSource:(int)arg1 withOptions:(id)arg2;
- (BOOL)isUILocked;
@end

@interface SBIconController : NSObject
+ (id)sharedInstance;
@end

@interface SBRootFolderController : NSObject
- (BOOL)setCurrentPageIndex:(int)arg1 animated:(int)arg2;
@end

@interface SBAppStatusBarManager : NSObject
+ (id)sharedInstance;
- (void)hideStatusBar;
@end

@interface SBWorkspaceApplicationTransitionContext : NSObject
@property(nonatomic) _Bool animationDisabled; // @synthesize animationDisabled=_animationDisabled;
- (void)setEntity:(id)arg1 forLayoutRole:(int)arg2;
@end

@interface SBWorkspaceDeactivatingEntity : NSObject
@property(nonatomic) long long layoutRole; // @synthesize layoutRole=_layoutRole;
+ (id)entity;
@end

@interface SBWorkspaceHomeScreenEntity : NSObject
@end

@interface SBMainWorkspaceTransitionRequest : NSObject
- (id)initWithDisplay:(id)arg1;
@end

@interface SBAppToAppWorkspaceTransaction : NSObject
- (void)begin;
- (void)setCompletionBlock:(id)arg1;
- (void)transaction:(id)arg1 performTransitionWithCompletion:(id)arg2;
- (id)initWithAlertManager:(id)alertManager exitedApp:(id)app;
- (id)initWithAlertManager:(id)arg1 from:(id)arg2 to:(id)arg3 withResult:(id)arg4;
- (id)initWithTransitionRequest:(id)arg1;
@end

@interface FBWorkspaceEvent : NSObject
+ (instancetype)eventWithName:(NSString *)label handler:(id)handler;
@end

@interface FBWorkspaceEventQueue : NSObject
+ (instancetype)sharedInstance;
- (void)executeOrAppendEvent:(FBWorkspaceEvent *)event;
@end

@interface SBDeactivationSettings : NSObject
-(id)init;
-(void)setFlag:(int)flag forDeactivationSetting:(unsigned)deactivationSetting;
@end

@interface UIApplication (Private) 
- (id)_accessibilityFrontMostApplication;
@end

@interface UIWindow (Private)
+ (id)keyWindow;
@end

@interface SBApplication : NSObject
@property(copy, nonatomic, setter=_setDeactivationSettings:) SBDeactivationSettings *_deactivationSettings;
- (void)setDeactivationSetting:(unsigned int)setting value:(id)value;
@end

