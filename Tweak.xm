#import "pasta.h"

//"sb_to_bb_snapshot_provider" is created in backboardd's mem space, and is accessible to 
//BKSystemAppSentinel and PUIProgressWindow. It stores the NSData representation of the springboard uimage,
//"prettyRespringQueued" which is the state in which the SB image will be replacing the apple logo, 
//and "recoveringFromPrettyRespring", which is SB coming back and picking the image back up
@implementation sb_to_bb_snapshot_provider

+ (id)sharedInstance {
	static dispatch_once_t p = 0;
	__strong static id _sharedObject = nil;

	dispatch_once(&p, ^{
		_sharedObject = [[self alloc] init];
	});

	return _sharedObject;
}

- (UIImage *)getSpringboardImage {
	return [[UIImage alloc] initWithData:[self sbSnapshotData]];
}

- (void)setSpringboardImage:(NSData *)data {
	_sbSnapshotData = [[NSData alloc] initWithData:data];
}

@end

//BKSystemAppSentinel is a class in backboardd that gets system app (springboard) state change notifications
%hook BKSystemAppSentinel

- (id)init {

	//when backboardd is created, set up the initial values for sb_to_bb_snapshot_provider
	[[sb_to_bb_snapshot_provider sharedInstance] setPrettyRespringQueued:NO];
	[[sb_to_bb_snapshot_provider sharedInstance] setRecoveringFromPrettyRespring:NO];

	//create a server that receives messages from springboard and sends them to 'receiveSpringBoardImage'
	CFMessagePortRef port = CFMessagePortCreateLocal(kCFAllocatorDefault, springToBackPortName, &receiveSpringBoardImage, NULL, NULL);
	CFMessagePortSetDispatchQueue(port, dispatch_get_main_queue());

	return %orig;
}

//this method is sent a snapshot of springboard, as NSData. msgid should be 'springboardServerToBackboardRemote'
CFDataRef receiveSpringBoardImage(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {

	//create new instance of data in this memory space
	NSData *imageData = [[NSData alloc] initWithData:(NSData *)data];
	if (msgid != springboardServerToBackboardRemote) {
		NSLog(@"dont recognize sender");
	}

	//confirm nothing weird happened in transit
	if (![imageData isKindOfClass:[NSData class]]) {
		NSLog(@"backboardd received corrupt image data");
		return NULL;
	}

	//send image to snapshot provider, and queue the apple logo to be replaced with it
	[[sb_to_bb_snapshot_provider sharedInstance] setSpringboardImage:imageData];
	[[sb_to_bb_snapshot_provider sharedInstance] setPrettyRespringQueued:YES];

	[imageData release];

	return NULL;
}

//this gets hit a few seconds before springboard gets created
- (void)server:(id)server systemAppCheckedIn:(BKSystemApplication *)application completion:(void (^)())complete {
	
	//completion block so we run after SB
	void (^newCompletion)() = ^{

		//do original completion first
		complete();

		//confirm this system app is springboard
		if ([[application bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {

			//recoveringFromPrettyRespring == 1 and having an image of SB means we're finishing the transition back to HS
			if ([[sb_to_bb_snapshot_provider sharedInstance] recoveringFromPrettyRespring] && [[sb_to_bb_snapshot_provider sharedInstance] getSpringboardImage]) {

				//we need to ensure SB is already done loading before we create remote server to it
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{

					//connect remote to SB
					CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, backToSpringPortName);
					if (port > 0) {

						//get NSData representation of the cached SB image
						NSData *imageData = UIImagePNGRepresentation([[sb_to_bb_snapshot_provider sharedInstance] getSpringboardImage]);

						//send the image back to springboard
						SInt32 req = CFMessagePortSendRequest(port, backboardRemoteToSpringboardServer, (CFDataRef)imageData, 1000, 0, NULL, NULL);
						if (req != kCFMessagePortSuccess) {

							NSLog(@"error with message request from backboardd to springboard");
						}

						//close connection
						CFMessagePortInvalidate(port);
						[imageData release];
					}
					else {

						NSLog(@"error, failed to create remote server: %s", strerror(errno));
					}

					//reset our flag so we dont do it again unwarrented
					[[sb_to_bb_snapshot_provider sharedInstance] setRecoveringFromPrettyRespring:NO];
				});
			}
		}
		else {

			NSLog(@"checked in system app is not springboard");
		}
	};

	%orig(server, application, newCompletion);
}

%end

//this is the respring iosurface
%hook PUIProgressWindow

//normally, arg1 would be "apple-logo-xx", I zero them out since we dont need it
- (id)_createImageWithName:(const char *)arg1 scale:(int)arg2 displayHeight:(int)arg3 {

	//if we have a cached SB image, and are queued to be pretty
	UIImage *snapImage = [[sb_to_bb_snapshot_provider sharedInstance] getSpringboardImage];
	if (snapImage && [[sb_to_bb_snapshot_provider sharedInstance] prettyRespringQueued]) {

		//get main layer of surface, and add image onto it
		CALayer *surfaceLayer = [self valueForKey:@"_layer"];
		UIImageView *springImageView = [[UIImageView alloc] initWithFrame:[surfaceLayer frame]];
		[springImageView setImage:snapImage];
		[surfaceLayer addSublayer:[springImageView layer]];
		[springImageView release];
		[snapImage release];

		//set flag to create fancy respring iosurface (^that) to no
		[[sb_to_bb_snapshot_provider sharedInstance] setPrettyRespringQueued:NO];

		//we want springboard to take the image and animate back to the homescreen when it respawns
		[[sb_to_bb_snapshot_provider sharedInstance] setRecoveringFromPrettyRespring:YES];

		//call original function, void of the apple logo layer
		return %orig("", 0, 0);
	}

	//normal boot or respring
	return %orig;

}

%end

%hook SBUIController

- (id)init {

	//let backboardd send messages to this process, at callback function shouldResumePrettyRespring
	CFMessagePortRef port = CFMessagePortCreateLocal(kCFAllocatorDefault, backToSpringPortName, &shouldResumePrettyRespring, NULL, NULL);
	CFMessagePortSetDispatchQueue(port, dispatch_get_main_queue());

	return %orig;
}

- (void)handleVolumeEvent:(id)event {

	[[UIApplication sharedApplication] performSelector:@selector(_relaunchSpringBoardNow)];
}

//this gets when springboard respawns, and needs to pick back up where it left off and animate to the HS from the image
CFDataRef shouldResumePrettyRespring(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {

	if (msgid != backboardRemoteToSpringboardServer) {
		NSLog(@"sender isnt recognized");
	}

	//data is NSData representation of the springboard uiimage stored in backboardd
	NSData *imageData = [[NSData alloc] initWithData:(NSData *)data];
	if (![imageData isKindOfClass:[NSData class]]) {
		NSLog(@"springboard received corrupt image data");
		return NULL;
	}

	//get uiimage from data
	UIImage *springboardSnap = [UIImage imageWithData:imageData];
	[imageData release];

	//create topmost window to cover lockscreen until we get to the homescreen
	UIWindow *frontWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	[frontWindow setWindowLevel:9999];
	[frontWindow makeKeyAndVisible];

	//add cached springboard image to window
	UIImageView *snapImage = [[UIImageView alloc] initWithFrame:[frontWindow frame]];
	[snapImage setImage:springboardSnap];
	[frontWindow addSubview:snapImage];
	[springboardSnap release];

	//attempt to go straight to the homescreen
	NSDictionary *options = @{ @"SBUIUnlockOptionsNoPasscodeAnimationKey" : [NSNumber numberWithBool:YES],
								@"SBUIUnlockOptionsBypassPasscodeKey" : [NSNumber numberWithBool:YES] };
	/*
	if ((r5 & 0xff) == 0x0) {
            r0 = r8->_disableLockScreenIfPossibleAssertions;
            r0 = [r0 count];
            if ((r6 & 0xff) != 0x0) {
                    CMP(r0, 0x0);
            }
    */  //I guess ill just add something fake to the lock assertions??
	[[[objc_getClass("SBLockScreenManager") sharedInstance] valueForKey:@"_disableLockScreenIfPossibleAssertions"] addObject:@"UNLOCK_PLZ"];

	[[objc_getClass("SBLockScreenManager") sharedInstance] unlockUIFromSource:0xbeef withOptions:options];

	//animate the window out
	[UIView animateWithDuration:1.5f animations:^{

		[frontWindow setAlpha:0.0];
	} completion:^(BOOL completed) {

		//at this point we're back home
		[frontWindow removeFromSuperview];
		[frontWindow release];
	}];

	return NULL;
}

%end

%hook SpringBoard

//we can only really do the fancy respring if this method is called, not 'killall SpringBoard'
- (void)_relaunchSpringBoardNow {

	//put all the work into a block
	void (^prettyRespringBlock)() = ^{

		double delayInSeconds = 2.2f;
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

	        //snapshot the screen
			UIView *screenView = [[UIScreen mainScreen] snapshotViewAfterScreenUpdates:YES];
			[screenView setAlpha:0.1f];

	        //create darkening view
			UIView *coverView = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
			[coverView setBackgroundColor:[UIColor blackColor]];
			[coverView setAlpha:0.0f];
			[screenView addSubview:coverView];
			[coverView release];

	        //create blur layer
			CAFilter *filter = [CAFilter filterWithType:@"gaussianBlur"];
			[filter setValue:[NSNumber numberWithFloat:3.0f] forKey:@"inputRadius"];
			[filter setValue:[NSNumber numberWithBool:YES] forKey:@"inputHardEdges"];

	        //add the blur to the snapshots layer
			CALayer *layer = [screenView layer];
			[layer setFilters:@[filter]];
			[layer setShouldRasterize:YES];

	        // add the subview
			[[UIWindow keyWindow] addSubview:screenView];

	        //begin the darkening/blurring animation
			[UIView animateWithDuration:1.5f delay:0 options:UIViewAnimationCurveEaseIn animations:^{

				[screenView setAlpha:1.0f];
				[coverView setAlpha:0.4f];

			} completion:^(BOOL completed){

				if (completed) {

					//stop rasterizing now that animation is over
					[layer setShouldRasterize:NO];

	            	//dont want a big unblurred statusbar on the view
					[[objc_getClass("SBAppStatusBarManager") sharedInstance] hideStatusBar];

	            	//when done, get a uiimage of the final blurred view
					UIGraphicsBeginImageContextWithOptions([screenView frame].size, NO, 0);
					[screenView drawViewHierarchyInRect:[screenView frame] afterScreenUpdates:YES];
					UIImage *snapshotImage = UIGraphicsGetImageFromCurrentImageContext();
					UIGraphicsEndImageContext();

					[screenView release];
					[layer release];

	            	//open remote server to backboardd
					CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, springToBackPortName);
					if (port > 0) {

				    	//get nsdata from the snapshot
						NSData *imageData = UIImagePNGRepresentation(snapshotImage);

				    	//send the data to backboardd, it will get taken by the 'receiveSpringBoardImage' function
						SInt32 req = CFMessagePortSendRequest(port, springboardServerToBackboardRemote, (CFDataRef)imageData, 1000, 0, NULL, NULL);
						if (req != kCFMessagePortSuccess) {

							NSLog(@"error with message request from springboard to backboardd");
						}

				    	//close the connection
						CFMessagePortInvalidate(port);
						[imageData release];
					}
					else {

						NSLog(@"error, failed to create remote server: %s", strerror(errno));
					}

					//and do the respring
					%orig;
				}

			}];
		});
	};

	//if an app is open, close to the homescreen
	if ([[UIApplication sharedApplication] _accessibilityFrontMostApplication]) {

		FBWorkspaceEvent *event = [NSClassFromString(@"FBWorkspaceEvent") eventWithName:@"ActivateSpringBoard" handler:^{

			SBDeactivationSettings *deactiveSets = [[NSClassFromString(@"SBDeactivationSettings") alloc] init];
			[deactiveSets setFlag:YES forDeactivationSetting:20];
			[deactiveSets setFlag:NO forDeactivationSetting:2];
			[[[UIApplication sharedApplication] _accessibilityFrontMostApplication] _setDeactivationSettings:deactiveSets];
			[deactiveSets release];

			SBWorkspaceApplicationTransitionContext *transitionContext = [[NSClassFromString(@"SBWorkspaceApplicationTransitionContext") alloc] init];

            //set layout role to 'side' (deactivating)
			SBWorkspaceDeactivatingEntity *deactivatingEntity = [NSClassFromString(@"SBWorkspaceDeactivatingEntity") entity];
			[deactivatingEntity setLayoutRole:3];
			[transitionContext setEntity:deactivatingEntity forLayoutRole:3];

            //set layout role for 'primary' (activating)
			SBWorkspaceHomeScreenEntity *homescreenEntity = [[NSClassFromString(@"SBWorkspaceHomeScreenEntity") alloc] init];
			[transitionContext setEntity:homescreenEntity forLayoutRole:2];

            //create transititon request
			SBMainWorkspaceTransitionRequest *transitionRequest = [[NSClassFromString(@"SBMainWorkspaceTransitionRequest") alloc] initWithDisplay:[[UIScreen mainScreen] valueForKey:@"_fbsDisplay"]];
			[transitionRequest setValue:transitionContext forKey:@"_applicationContext"];

            //create apptoapp transaction
			SBAppToAppWorkspaceTransaction *transaction = [[NSClassFromString(@"SBAppToAppWorkspaceTransaction") alloc] initWithTransitionRequest:transitionRequest];

			//i do the transaction manually so i can know exactly when its finished.
			//sbapptoappworkspacetransaction inherits '_completionBlock' from baseboard's BSTransaction
			[transaction setCompletionBlock:^{

				//do the pretty respring when the app finished closing
				prettyRespringBlock();
			}];

			//start closing
			[transaction begin];

	}];

	//all transactions need to be on an event queue
	FBWorkspaceEventQueue *transactionEventQueue = [NSClassFromString(@"FBWorkspaceEventQueue") sharedInstance];
	[transactionEventQueue executeOrAppendEvent:event];

	}
	else {

		//make sure we are on the first homescreen page
		[(SBRootFolderController *)[[objc_getClass("SBIconController") sharedInstance] valueForKey:@"_rootFolderController"] setCurrentPageIndex:0 animated:YES];

		//already on the homescreen, just pretty respring
		prettyRespringBlock();
	}
}

%end