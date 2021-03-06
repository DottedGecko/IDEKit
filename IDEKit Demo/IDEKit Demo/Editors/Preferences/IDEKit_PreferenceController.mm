//
//  IDEKit_PreferenceController.mm
//
//  Copyright (c) 2003, 2004 by Glenn Andreas
//
//  This library is free software; you can redistribute it and/or
//  modify it under the terms of the GNU Library General Public
//  License as published by the Free Software Foundation; either
//  version 2 of the License, or (at your option) any later version.
//
//  This library is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//  Library General Public License for more details.
//
//  You should have received a copy of the GNU Library General Public
//  License along with this library; if not, write to the Free
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

#import "IDEKit_PreferenceController.h"
#import <PreferencePanes/NSPreferencePane.h>
#import <mach-o/dyld.h>
#import "IDEKit_PreferencePane.h"
#import "IDEKit_Delegate.h"
#import "IDEKit_PathUtils.h"

@implementation IDEKit_PreferenceController

+ (IDEKit_PreferenceController *)applicationPreferences
{
    static IDEKit_PreferenceController *gAppPrefs = NULL;
    if (!gAppPrefs) {
		gAppPrefs = [[IDEKit_AppPreferenceController alloc] initWithDefaults: [NSUserDefaults standardUserDefaults]];
    }
    return gAppPrefs;
}

- (void) buildPanelList
{
    NSArray *array = [[NSBundle mainBundle] pathsForResourcesOfType: @"prefPane" inDirectory: @"PreferencePanes"];
    // and for now, just blindly add it
    for (NSUInteger i=0;i<[array count];i++) {
		NSBundle *prefBundle = [NSBundle bundleWithPath: array[i]];
		//NSLog(@"Examinging %@ info %@",prefBundle,[prefBundle infoDictionary]);
		NSString *category = [self categoryKeyFromBundle: prefBundle];
		if (!category) continue; // don't show this one
		[myPanels addObject: prefBundle];
		if (![myCategories containsObject: category]) {
			[myCategories addObject: category];
			myCategoryMap[category] = [NSMutableArray arrayWithCapacity: 1];
		}
		[myCategoryMap[category] addObject: prefBundle];
    }
}
- (NSString *)categoryKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_PreferenceCategory"];
}

- (NSString *)nameKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_PreferenceName"];
}

- (NSString *)nibName
{
    // we use the same panel for all the preference/settings.
    // We could use different ones, but that normally isn't needed
    return @"IDEKit_Preferences";
}

- (id) initWithDefaults: (NSUserDefaults *)defaults
{
    self = [super init];
    if (self) {
		myPanels = [NSMutableArray arrayWithCapacity: 0];
		myCategories = [NSMutableArray arrayWithCapacity: 0];
		myCategoryMap = [NSMutableDictionary dictionaryWithCapacity: 0];
		myDefaults = defaults;
    }
    return self;
}
- (void) dealloc
{
    [myPreferenceWindow close];
}

- (BOOL) loadUI
{
    if (!myPreferenceWindow) {
		if (![NSBundle loadOverridenNibNamed:[self nibName] owner:self])  {
			NSLog(@"Failed to load %@.nib",[self nibName]);
			NSBeep();
			return NO;
		}
		[myPreferenceHeader setCell: [[NSTableHeaderCell alloc] initTextCell: @""]];
		[self buildPanelList];
		[myPreferenceList reloadData];
		//[myPreferenceList expandItem: NULL expandChildren: YES];
		NSUInteger i = 0;
		while (i < [myPreferenceList numberOfRows]) {
			id item = [myPreferenceList itemAtRow: i];
			if ([myPreferenceList isExpandable: item]) {
				[myPreferenceList expandItem: item expandChildren: YES];
			}
			i++;
		}
    }
    NSInteger firstItem = [myPreferenceList numberOfRows] - 1;
    if (firstItem > 1) firstItem = 1;
    [myPreferenceList selectRow: firstItem byExtendingSelection: NO];
    [self switchPanel: myPreferenceList];
    return YES;
}
- (void) preferences
{
    isSheet = NO;
    [self loadUI];
    [myPreferenceWindow makeKeyAndOrderFront: self];
    [self switchPanel: self];
}

- (void) beginSheetModalForWindow:(NSWindow *)docWindow modalDelegate:(id)delegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
    isSheet = YES;
    [self loadUI];
    //[myPreferenceWindow retain];
    [NSApp beginSheet: myPreferenceWindow modalForWindow: docWindow modalDelegate: delegate didEndSelector: didEndSelector contextInfo:contextInfo];
}

- (void) revertToFactory: (id) sender
{
    NSDictionary *defaults = [IDEKit factoryDefaultUserSettings];
    NSArray *properties = [myCurrentPreferencePanel editedProperties];
    
    for (NSUInteger i=0;i<[properties count];i++) {
		id propertyName = properties[i];
		id defaultValue = defaults[propertyName];
		if (defaultValue) {
			[myDefaults setObject: defaultValue forKey: propertyName];
		}
    }
    [myCurrentPreferencePanel setMyDefaults: myDefaults]; // make sure we are using the current defaults (just in case)
    [myCurrentPreferencePanel didSelect]; // resend the select message to reload
}

- (void) exportPanel: (id) sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setPrompt: @"Export"];
    [panel setTitle: @"Export panel settings"];
	[panel setAllowedFileTypes:@[@"plist"]];
    if ([panel runModal] == NSOKButton) {
		NSString *path = [[panel URL] absoluteString];
		NSDictionary *data = [myCurrentPreferencePanel exportPanel];
		if (data) {
			[data writeToFile: path atomically: NO];
		}
    }
}

- (void) importPanel: (id) sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setTitle: @"Import panel settings"];
    [panel setPrompt: @"Import"];
	[panel setCanChooseDirectories:NO];
	[panel setCanChooseFiles:YES];
	[panel setAllowedFileTypes:@[@"plist"]];
	
    if ([panel runModal] == NSOKButton) {
		NSString *path = [(NSURL*)[panel URLs][0] absoluteString];
		NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile: path];
		if (data) {
			[myCurrentPreferencePanel importPanel: data];
		}
    }
}

- (void) donePreferences: (id) sender
{
    //NSLog(@"Done with preference");
    if (![myPreferenceWindow makeFirstResponder: NULL]) {
        //NSLog(@"Couldn't make firstResponder NULL");
		return;
    }
    //[myDefaults synchronize];
    if (isSheet) {
        //NSLog(@"Trying to close sheet");
		if ([myCurrentPreferencePanel shouldUnselect] == NSUnselectCancel) {
			//NSLog(@"Couldn't unselect");
			return;
		}
		//NSLog(@"EndSheet");
		[NSApp endSheet: myPreferenceWindow];
		[myPreferenceWindow orderOut: self];
		//[myPreferenceWindow release];
    } else {
        //NSLog(@"Trying to close window");
		//[myPreferenceWindow performClose: self]; // without the close button, this doesn't work
        if ([self windowShouldClose: myPreferenceWindow]) {
            [myPreferenceWindow close];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName: IDEKit_UserSettingsChangedNotification object: myDefaults];
}
- (BOOL) windowShouldClose: (NSWindow *)window
{
    if (window == myPreferenceWindow) {
        //NSLog(@"windowShouldClose myPreferenceWindow");
        if ([myCurrentPreferencePanel shouldUnselect] == NSUnselectCancel) {
            //NSLog(@"can't unselect");
			return NO;
        }
		[[myCurrentPreferencePanel mainView] removeFromSuperview]; /* Remove view from window */
		myCurrentPreferencePanel = NULL;
		//[myPreferenceWindow orderOut: self];
    }
    return YES;
}
- (void) switchPanel: (id) sender
{
    if ([myPreferenceList numberOfSelectedRows] == 0)
		return;
    NSBundle *prefBundle = [myPreferenceList itemAtRow: [myPreferenceList selectedRow]];
    if (![prefBundle isLoaded]) {
		//NSLog(@"Loading bundle %@",prefBundle);
		if (![prefBundle load]) {
			NSLog(@"Problems loading bundle %@/%@/%@???",prefBundle,[prefBundle principalClass],[[prefBundle infoDictionary] description]);
			return;
		}
    }
    Class prefPaneClass = [prefBundle principalClass];
    //NSLog(@"Switching to pane of class %@ in %@",prefPaneClass,prefBundle);
    if (myCurrentPreferencePanel) { // is something already up?
		if (![myPreferenceWindow makeFirstResponder: NULL])
			return;
		if ([myCurrentPreferencePanel isMemberOfClass: prefPaneClass])
			return; // we're already there
		if ([myCurrentPreferencePanel shouldUnselect] == NSUnselectCancel)
			return; // can't leave current panel (not quite right)
		[[myCurrentPreferencePanel mainView] removeFromSuperview]; /* Remove view from window */
		myCurrentPreferencePanel = NULL;
    }
    [myPreferenceHeader setStringValue: [self nameKeyFromBundle: prefBundle]];
	
    myCurrentPreferencePanel = [[prefPaneClass alloc]
								initWithBundle:prefBundle];
    //NSLog(@"About to set panel with defaults %@",myDefaults);
    if ([myCurrentPreferencePanel respondsToSelector: @selector(setMyDefaults:)]) {// and it should, since PeROXIDEPrefsPane does
		[myCurrentPreferencePanel setMyDefaults: myDefaults]; // use the defaults accordingly
		[myCurrentPreferencePanel setPathVars: [self getPathVars]];
    } else {
		NSLog(@"%@ doesn't respond to setMyDefaults:????",myCurrentPreferencePanel);
		//[myCurrentPreferencePanel setMyDefaults: myDefaults]; // do it anyway
    }
    NSView *prefView;
    if ( [myCurrentPreferencePanel loadMainView] ) {
		[myCurrentPreferencePanel willSelect];
		prefView = [myCurrentPreferencePanel mainView];
		[myPreferencePane addSubview: prefView]; /* Add view to window */
		[myCurrentPreferencePanel didSelect];
    } else {
		/* loadMainView failed -- handle error */
		NSBeep();
		return;
    }
}

- (id) outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (item == NULL) {
		return myCategories[index];
    } else {
		return myCategoryMap[item][index];
    }
}
- (id) outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    if ([item isKindOfClass: [NSBundle class]])
		return [self nameKeyFromBundle: item];
    else
		return item; // which is already a string
}
- (BOOL) outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return ![item isKindOfClass: [NSBundle class]];
}
- (NSInteger) outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (item == NULL) {
		return [myCategories count];
    } else {
		return [myCategoryMap[item] count];
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    if ([outlineView isExpandable: item])
		return NO;
    return YES;
}


+ (NSDictionary *)pathVars
{
    // overlay user paths on top of built in
    id userPaths = [[NSUserDefaults standardUserDefaults] objectForKey: IDEKit_UserPathsKey];
    id retval = [[IDEKit predefinedPathsVars] mutableCopy];
    for (NSUInteger i=0;i<[userPaths count];i++) {
		id entry = userPaths[i];
		retval[entry[0]] = entry[1];
    }
    return retval;
}

+ (NSString *)pathWithVars: (NSString *)path
{
    return [path stringByReplacingVars: [self pathVars]];
}
- (NSDictionary *)getPathVars
{
    return [[self class] pathVars];
}

@end


@implementation IDEKit_AppPreferenceController
- (NSString *)categoryKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_AppPrefCategory"];
}

- (NSString *)nameKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_AppPrefName"];
}
@end
@implementation IDEKit_LayeredPreferenceController
- (void) revertToFactory: (id) sender
{
    // for the app, "revertToFactory" reverts to our factory defaults.  For a layered settings,
    // we want to revert to what was under our layer (so we will revert to the application preference defined font,
    // instead of the factory defined font).
    NSArray *properties = [myCurrentPreferencePanel editedProperties];
	
    for (NSUInteger i=0;i<[properties count];i++) {
		id propertyName = properties[i];
		[myDefaults removeObjectForKey: propertyName]; // this make us remove the settings that overshadow our current preferences
    }
    [myCurrentPreferencePanel setMyDefaults: myDefaults]; // make sure we are using the current defaults (just in case)
    [myCurrentPreferencePanel didSelect]; // resend the select message to reload
}
@end
@implementation IDEKit_SrcPreferenceController
- (NSString *)categoryKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_SrcPrefCategory"];
}

- (NSString *)nameKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_SrcPrefName"];
}


@end
@implementation IDEKit_ProjectPreferenceController
- (id) initWithDefaults: (NSUserDefaults *)defaults forProject: (id) project
{
    self = [super initWithDefaults: defaults];
    if (self) {
		myProject = project;
    }
    return self;
}

- (NSDictionary *)getPathVars
{
    // get's the paths for the project itself
    return [myProject pathVars];
}

- (NSString *)categoryKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_ProjPrefCategory"];
}

- (NSString *)nameKeyFromBundle: (NSBundle *) prefBundle
{
    return [prefBundle infoDictionary][@"IDEKit_ProjPrefName"];
}
@end
