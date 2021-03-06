//
//  IDEKit_TextViewExtensions.mm
//  IDEKit
//
//  Created by Glenn Andreas on Sun Aug 17 2003.
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
//

#import "IDEKit_TextViewExtensions.h"
#import "IDEKit_Delegate.h"
#import "IDEKit_PathUtils.h"
#import "IDEKit_Autocompletion.h"

@implementation NSObject (IDEKit_NSTextViewExtendedDelegate)
- (BOOL)textView:(NSTextView *)textView shouldInterpretKeyEvents: (NSArray *)eventArray
{
    return YES;
}
@end

@implementation NSTextView(IDEKit_TextViewExtensions)
- (NSFont *)currentFont
{
    // get the current font
    NSFont *font;
    if ([[self textStorage] length] == 0)
		font = [self typingAttributes][NSFontAttributeName]; // Get the font of the typing attribute if no text
    else
		font = [[self textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    font = [[self layoutManager] substituteFontForFont:font]; // see if there is a substitute font
    return font;
}

- (NSRange) visibleRange
{
    NSRect visRect = [self visibleRect];
    NSUInteger firstGlyph = [[self layoutManager] glyphIndexForPoint: visRect.origin inTextContainer:  [self textContainer]];
    NSUInteger lastGlyph = [[self layoutManager] glyphIndexForPoint: NSMakePoint(visRect.origin.x + visRect.size.width, visRect.origin.y + visRect.size.height) inTextContainer:  [self textContainer]];
    NSUInteger firstChar = [[self layoutManager] characterIndexForGlyphAtIndex: firstGlyph];
    NSUInteger lastChar = [[self layoutManager] characterIndexForGlyphAtIndex: lastGlyph];
    return NSMakeRange(firstChar,lastChar-firstChar);
}

#pragma mark Line Numbers
- (NSRange) nthLineRange: (NSInteger) n
{
    // line num are 1 based
    if (n == 0) return NSMakeRange(0,0);
    NSString *text = [self string];
    return [text nthLineRange: n];
}
- (NSInteger) lineNumberFromOffset: (NSUInteger) offset
{
    NSString *text = [self string];
    return [text lineNumberFromOffset: offset];
}

- (void) selectNthLine: (NSInteger) line
{
    NSRange range = [self nthLineRange: line];
    [self setSelectedRange: range];
    [self scrollRangeToVisible: range];
}

#pragma mark Tab Stops
- (float) indentWidthFromSpaces: (float) num
{
    // get the current font
    NSFont *font;
    if ([[self textStorage] length] == 0)
		font = [self typingAttributes][NSFontAttributeName]; // Get the font of the typing attribute if no text
    else
		font = [[self textStorage] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    font = [[self layoutManager] substituteFontForFont:font]; // see if there is a substitute font
    float spaceWidth = 0.0;
    // should we actually use spaces?  Or "n" spaces?
    if ((NSGlyph)' ' < [font numberOfGlyphs]) {
		spaceWidth = [font advancementForGlyph:(NSGlyph)' '].width;
    } else {
		spaceWidth = [font maximumAdvancement].width;
    }
    if (num == 0.0)
		return spaceWidth * 4.0; // default to 4 "spaces" per indent
    return num * spaceWidth;
}

- (void) setUniformTabStops: (float) tabStops
{
    // with 10.3 we should use setDefaultTabInterval as well/instead
    if (tabStops == 0.0 || (tabStops != tabStops)) // just in case we pass NaN
		tabStops = 36.0;
    if (tabStops < 0.0)
		tabStops = [self indentWidthFromSpaces: -tabStops];
    if (tabStops < 72.0 / 8.0)
		tabStops = 72.0 / 8.0; // regardless, don't let them be smaller than an 1/8th of an inch
    //if (tabStops == myTabStops)
	//return;
    //NSLog(@"Changing tab stops to be every %g",tabStops);
    //myTabStops = tabStops;
    // get the default value for the paragraph
    NSMutableParagraphStyle *m = [[IDEKit defaultParagraphStyle] mutableCopy];
    // and now change the tabs - make tabs all the way out to 12.0 (Units?)
    NSMutableArray *tabArray = [NSMutableArray array];
    float pos = tabStops;
    //NSLog(@"Adding tabs every %g",pos);
    while (pos < 12.0 * 72.0) {
		NSTextTab *tabStop = [[NSTextTab alloc] initWithType: NSLeftTabStopType location: pos];
		[tabArray addObject:tabStop];
		pos += tabStops;
    }
    //NSLog(@"style was %@",[m description]);
    //NSLog(@"Adding tab stops %@",[tabArray description]);
    [m setTabStops: tabArray];
    //NSLog(@"style now %@",[m description]);
    // note that if the text is empty, this will get lost, so in our "setString" we override it to reset the tabs
    [[self textStorage] addAttribute:NSParagraphStyleAttributeName
							   value:m range:NSMakeRange(0, [[self textStorage] length])];
    // make sure we are typing with these attributes (handles blank documents as well)
    NSMutableDictionary *attributes = [[self typingAttributes] mutableCopy];
    attributes[NSParagraphStyleAttributeName] = m;
    //NSLog(@"typing attributes now %@",[attributes description]);
    [self setTypingAttributes:attributes];
    //NSLog(@"Text attributes changed to %@",[m description]);
}

- (void) filterRangeToAscii: (NSRange) range
{
    NSMutableString *s = [[self textStorage] mutableString];
    for (NSUInteger i=0;i<range.length;i++) {
		unichar c = [s characterAtIndex: range.location + i];
		if (c >= 0x80) {
			NSString *littleString = [NSString stringWithFormat: @"%C",c];
			NSData *converted = [littleString dataUsingEncoding: NSASCIIStringEncoding allowLossyConversion: YES];
			if (converted && [converted length] >= 1) {
				char strippedChar;
				[converted getBytes: &strippedChar range: NSMakeRange(0,1)];
				[s replaceCharactersInRange: NSMakeRange(range.location + i,1) withString: [NSString stringWithFormat: @"%c",strippedChar]];
			} else {
				// it was going to drop it completely, so replace with something to keep the length the
				// same (?)
				if ([[NSCharacterSet punctuationCharacterSet] characterIsMember: c])
					[s replaceCharactersInRange: NSMakeRange(range.location + i,1) withString: @"."];
				else if (([[NSCharacterSet controlCharacterSet] characterIsMember: c])) // unicode control character
					[s replaceCharactersInRange: NSMakeRange(range.location + i,1) withString: @" "];
				else if (0x2190 <= c && c <= 0x21ff) // arrows
					[s replaceCharactersInRange: NSMakeRange(range.location + i,1) withString: @"-"];
				else if (0x2500 <= c && c <= 0x25ff) // box, block, geometric shapes
					[s replaceCharactersInRange: NSMakeRange(range.location + i,1) withString: @"#"];
				else if (0x2600 <= c && c <= 0x27bf) // misc symbols, dingbats
					[s replaceCharactersInRange: NSMakeRange(range.location + i,1) withString: @"*"];
				else
					[s replaceCharactersInRange: NSMakeRange(range.location + i,1) withString: @"?"];
			}
		}
    }
}

- (IBAction) filterSelectionToAscii: (id) sender;
{
    [self filterRangeToAscii: [self selectedRange]];
}

- (IBAction) filterAllToAscii: (id) sender
{
    [self filterRangeToAscii: NSMakeRange(0,[[self textStorage] length])];
}

#pragma mark Page Break
- (IBAction) insertPageBreak: (id) sender
{
    [self insertText: [NSString stringWithFormat: @"\n%d",0x000c]]; // Control-L is page break char
    // However, if this is not at the start of the line, the rest of the text vanishes to a non-existant
    // text container, so make sure that we are at the start of the line
}
#pragma mark Indenting

- (NSString *) getCurrentIndentLimited: (BOOL) limit
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    selectedRange.length = 0; // make sure that we work with the start of the range
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    if (limit && lineEndIndex > selectedRange.location)
		lineEndIndex = selectedRange.location; // only include up to where cursor is
    NSString *thisLine = [text substringWithRange: NSMakeRange(startIndex,lineEndIndex - startIndex)];
    return [thisLine leadingIndentString];
}
- (NSString *) getCurrentIndent
{
    return [self getCurrentIndentLimited: NO];
}

- (IBAction) insertNewlineRemoveIndent: (id) sender
{
    // similar to insertNewline, but it remove any leading indents - extend the selection to include them
    NSRange selectedRange = [self selectedRange];
    // start from after the end of the range
    NSUInteger endOfRange = selectedRange.location + selectedRange.length;
    NSString *text = [self string];
    while (endOfRange < [text length] && [[NSCharacterSet whitespaceCharacterSet] characterIsMember: [text characterAtIndex:endOfRange]])
		endOfRange++;
    [self setSelectedRange: NSMakeRange(selectedRange.location, endOfRange - selectedRange.location)];
    [self insertNewline: sender];
}

- (IBAction) insertNewlineAndIndent: (id) sender
{
    // first, figure out the indent
    NSString *indent = [[self getCurrentIndent] stringByAppendingString: @"\t"];
    // then actually insert the newline
    [self insertNewlineRemoveIndent: self];
    // then make the indent happen
    [self insertText: indent];
}
- (IBAction) insertNewlineAndDedent: (id) sender
{
    // first, figure out the indent
    NSString *indent = [self getCurrentIndent];
    if ([indent length]) {
        indent = [indent substringToIndex: [indent length] - 1];
    }
    // then actually insert the newline
    [self insertNewlineRemoveIndent: self];
    // then make the indent happen
    [self insertText: indent];
}
- (IBAction) insertNewlineAndDent: (id) sender
{
    // first, figure out the indent
    NSString *indent = [self getCurrentIndent];
	
    // then actually insert the newline
    [self insertNewlineRemoveIndent: self];
    // then make the indent happen
    [self insertText: indent];
}

- (IBAction) indent: (id) sender
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    NSInteger firstLine = [self lineNumberFromOffset: startIndex];
    NSInteger lastLine = [self lineNumberFromOffset: contentsEndIndex];
    for (NSInteger line = firstLine; line <= lastLine; line++) {
		NSRange lineRange = [self nthLineRange: line];
		lineRange.length = 0;
		[self setSelectedRange: lineRange];
		[self insertTab: self];
    }
    NSRange startOffset = [self nthLineRange: firstLine];
    NSRange lastOffset = [self nthLineRange: lastLine];
    [self setSelectedRange: NSUnionRange(startOffset,lastOffset)];
}
- (IBAction) dedent: (id) sender
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    NSInteger firstLine = [self lineNumberFromOffset: startIndex];
    NSInteger lastLine = [self lineNumberFromOffset: contentsEndIndex];
    for (NSInteger line=firstLine;line<=lastLine;line++) {
		NSRange lineRange = [self nthLineRange: line];
		if (lineRange.length) {
			unichar leadingChar = [text characterAtIndex: lineRange.location];
			if (leadingChar == '\t') {
				// just nuke the one tab
				lineRange.length = 1;
			} else if (leadingChar == ' ') {
				// nuke off up to four of them
				int spaceLen = 1;
				while (spaceLen < lineRange.length && spaceLen < 4) {
					if ([text characterAtIndex: lineRange.location + spaceLen] == ' ') {
						spaceLen++;
					} else {
						break;
					}
				}
				lineRange.length = spaceLen;
			} else
				continue; // do nothing
			[self setSelectedRange: lineRange];
			[self delete: self];
		}
    }
    NSRange startOffset = [self nthLineRange: firstLine];
    NSRange lastOffset = [self nthLineRange: lastLine];
    [self setSelectedRange: NSUnionRange(startOffset,lastOffset)];
}

- (IBAction) undent: (id) sender
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    NSInteger firstLine = [self lineNumberFromOffset: startIndex];
    NSInteger lastLine = [self lineNumberFromOffset: contentsEndIndex];
    for (NSInteger line=firstLine;line<=lastLine;line++) {
		NSRange lineRange = [self nthLineRange: line];
		if (lineRange.length) {
			// nuke off up to four of them
			int spaceLen = 0;
			while (spaceLen < lineRange.length) {
				if ([text characterAtIndex: lineRange.location + spaceLen] == ' ' || [text characterAtIndex: lineRange.location + spaceLen] == '\t') {
					spaceLen++;
				} else {
					break;
				}
			}
			if (spaceLen) {
				lineRange.length = spaceLen;
				[self setSelectedRange: lineRange];
				[self delete: self];
			}
		}
    }
    NSRange startOffset = [self nthLineRange: firstLine];
    NSRange lastOffset = [self nthLineRange: lastLine];
    [self setSelectedRange: NSUnionRange(startOffset,lastOffset)];
}

#pragma mark Balancing
- (NSInteger) balanceForwards: (NSInteger) location endCharacter: (unichar) rparen
{
    //NSLog(@"Looking forward from %d for %c",location,rparen);
    NSString *text = [self string];
    while (location < [text length]) {
		unichar c = [text characterAtIndex: location];
		if (c == rparen) {
			//NSLog(@"Found at %d",location);
			return location;
		}
		if (c == '(') {
			location = [self balanceForwards: location + 1 endCharacter: ')'] + 1;
		} else if (c == '[') {
			location = [self balanceForwards: location + 1 endCharacter: ']'] + 1;
		} else if (c == '{') {
			location = [self balanceForwards: location + 1 endCharacter: '}'] + 1;
		} else {
			location++;
		}
    }
    return location;
}

- (NSInteger) balanceBackwards: (NSInteger) location startCharacter: (unichar) lparen
{
    //NSLog(@"Looking backwards from %d for %c",location,lparen);
    NSString *text = [self string];
    location--;
    while (location >= 0) {
		unichar c = [text characterAtIndex: location];
		if (c == lparen) {
			//NSLog(@"Found at %d",location);
			return location;
		}
		if (c == ')') {
			location = [self balanceBackwards: location - 1 startCharacter: '('] - 1;
		} else if (c == ']') {
			location = [self balanceBackwards: location - 1 startCharacter: '['] - 1;
		} else if (c == '}') {
			location = [self balanceBackwards: location - 1 startCharacter: '{'] - 1;
		} else {
			location--;
		}
    }
    return location;
}

- (NSRange) balanceFrom: (NSInteger) location startCharacter: (unichar) lparen endCharacter: (unichar) rparen
{
    NSInteger start = [self balanceBackwards: location startCharacter: lparen];
    NSInteger end = [self balanceForwards: location endCharacter: rparen];
    if (start < 0 || end >= [(NSString*)[self string] length])
		return NSMakeRange(location,0);
    return NSMakeRange(start,end - start + 1);
}

- (NSRange) balanceFrom: (NSInteger) location
{
    NSRange range = NSMakeRange(0,[(NSString*)[self string] length]);
    NSRange range1 = [self balanceFrom: location startCharacter: '(' endCharacter: ')'];
    range = range1; //NSUnionRange(range,range1);
    range1 = [self balanceFrom: location startCharacter: '{' endCharacter: '}'];
    // every time we get a new range, if we are currently empty, use that, otherwise
    // use which ever one is inside the other one (or error if they just overlap)
    if (range.length == 0) {
		range = range1;
    } else if (range1.length == 0 || NSEqualRanges(range,NSIntersectionRange(range,range1))) {
		// range = range;
    } else if (NSEqualRanges(range1,NSIntersectionRange(range,range1))) {
		range = range1;
    } else {
		return NSMakeRange(location,0);
    }
	
    range1 = [self balanceFrom: location startCharacter: '[' endCharacter: ']'];
    if (range.length == 0) {
		range = range1;
    } else if (range1.length == 0 || NSEqualRanges(range,NSIntersectionRange(range,range1))) {
		// range = range;
    } else if (NSEqualRanges(range1,NSIntersectionRange(range,range1))) {
		range = range1;
    } else {
		return NSMakeRange(location,0);
    }
	
    return range;
}

- (IBAction) balance: (id) sender
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSRange balanceRange = [self balanceFrom: selectedRange.location];
    if (balanceRange.length) {
		[self setSelectedRange: balanceRange];
    } else {
		NSBeep();
    }
}

#pragma mark Prefixes
- (void) prefixSelectedLinesWith: (NSString *) prefix
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    NSInteger firstLine = [self lineNumberFromOffset: startIndex];
    NSInteger lastLine = [self lineNumberFromOffset: contentsEndIndex];
    for (NSInteger line=firstLine;line<=lastLine;line++) {
		NSRange lineRange = [self nthLineRange: line];
		if (lineRange.length == 0) // end of file, no newline on last line
			break;
		lineRange.length = 0; // go to start of line
		[self setSelectedRange: lineRange];
		[self insertText: prefix];
    }
    NSRange startOffset = [self nthLineRange: firstLine];
    NSRange lastOffset = [self nthLineRange: lastLine];
    [self setSelectedRange: NSUnionRange(startOffset,lastOffset)];
}
- (void) unprefixSelectedLinesWith: (NSString *) prefix
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    NSInteger firstLine = [self lineNumberFromOffset: startIndex];
    NSInteger lastLine = [self lineNumberFromOffset: contentsEndIndex];
    for (NSInteger line=firstLine;line<=lastLine;line++) {
		NSRange lineRange = [self nthLineRange: line];
		if (lineRange.length == 0) // end of file, no newline on last line
			break;
		if (lineRange.length >= [prefix length]) {
			lineRange.length = [prefix length];
			if ([[text substringWithRange: lineRange] isEqualToString: prefix]) {
				[self setSelectedRange: lineRange];
				[self delete: self];
			}
		}
    }
    NSRange startOffset = [self nthLineRange: firstLine];
    NSRange lastOffset = [self nthLineRange: lastLine];
    [self setSelectedRange: NSUnionRange(startOffset,lastOffset)];
}
- (void) suffixSelectedLinesWith: (NSString *) prefix
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    NSInteger firstLine = [self lineNumberFromOffset: startIndex];
    NSInteger lastLine = [self lineNumberFromOffset: contentsEndIndex];
    for (NSInteger line=firstLine;line<=lastLine;line++) {
		NSRange lineRange = [self nthLineRange: line];
		if (lineRange.length == 0) // end of file, no newline on last line
			break;
		lineRange.location += lineRange.length-1;
		lineRange.length = 0; // go to end of line
		[self setSelectedRange: lineRange];
		[self insertText: prefix];
    }
    NSRange startOffset = [self nthLineRange: firstLine];
    NSRange lastOffset = [self nthLineRange: lastLine];
    [self setSelectedRange: NSUnionRange(startOffset,lastOffset)];
}
- (void) unsuffixSelectedLinesWith: (NSString *) prefix
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *text = [self string];
    NSUInteger startIndex;
    NSUInteger lineEndIndex;
    NSUInteger contentsEndIndex;
    [text getLineStart: &startIndex end: &lineEndIndex contentsEnd: &contentsEndIndex forRange: selectedRange];
    NSInteger firstLine = [self lineNumberFromOffset: startIndex];
    NSInteger lastLine = [self lineNumberFromOffset: contentsEndIndex];
    for (NSInteger line=firstLine;line<=lastLine;line++) {
		NSRange lineRange = [self nthLineRange: line];
		if (lineRange.length == 0) // end of file, no newline on last line
			break;
		if (lineRange.length >= [prefix length]) {
			// go to the end of the line
			lineRange.location = lineRange.location + lineRange.length - 1 - [prefix length];
			lineRange.length = [prefix length];
			if ([[text substringWithRange: lineRange] isEqualToString: prefix]) {
				[self setSelectedRange: lineRange];
				[self delete: self];
			}
		}
    }
    NSRange startOffset = [self nthLineRange: firstLine];
    NSRange lastOffset = [self nthLineRange: lastLine];
    [self setSelectedRange: NSUnionRange(startOffset,lastOffset)];
}

// XML
- (IBAction) escapeXMLCharacters: (id) sender
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *portion;
    if (selectedRange.length == 0) {
		selectedRange.location = 0;
		selectedRange.length = [[self string] length];
		portion = [self string];
    } else {
		portion = [[self string] substringWithRange:selectedRange];
    }
    NSString *converted = [portion stringByEscapingXMLChars];
    [self setSelectedRange: selectedRange];
    [self insertText: converted];
    selectedRange.length = [converted length];
    [self setSelectedRange: selectedRange];
}
- (IBAction) unescapeXMLCharacters: (id) sender
{
    NSRange selectedRange = [self selectedRange]; // figure out the start of this line
    NSString *portion;
    if (selectedRange.length == 0) {
		selectedRange.location = 0;
		selectedRange.length = [[self string] length];
		portion = [self string];
    } else {
		portion = [[self string] substringWithRange:selectedRange];
    }
    NSString *converted = [portion stringFromEscapedXMLChars];
    [self setSelectedRange: selectedRange];
    [self insertText: converted];
    selectedRange.length = [converted length];
    [self setSelectedRange: selectedRange];
}

#pragma mark Insertion Point Popups
- (NSPoint) insertionPointWindowCoordinate
{
    NSRange range = [self selectedRange];
    NSRange glyphRange = [[self layoutManager] glyphRangeForCharacterRange: range actualCharacterRange: NULL];
    NSRect boundingRect = [[self layoutManager] boundingRectForGlyphRange: glyphRange inTextContainer: [self textContainer]];
    boundingRect = [self convertRect: boundingRect toView: NULL];
    return NSMakePoint(boundingRect.origin.x + boundingRect.size.width,boundingRect.origin.y + boundingRect.size.height / 2.0);
}

- (NSPoint) insertionPointLocalCoordinate
{
    NSRange range = [self selectedRange];
    NSRange glyphRange = [[self layoutManager] glyphRangeForCharacterRange: range actualCharacterRange: NULL];
    NSRect boundingRect = [[self layoutManager] boundingRectForGlyphRange: glyphRange inTextContainer: [self textContainer]];
    //boundingRect = [self convertRect: boundingRect toView: view];
    return NSMakePoint(boundingRect.origin.x + boundingRect.size.width,boundingRect.origin.y + boundingRect.size.height / 2.0);
}

- (NSPoint) insertionPointGlobalCoordinate
{
    NSRange range = [self selectedRange];
    NSRange glyphRange = [[self layoutManager] glyphRangeForCharacterRange: range actualCharacterRange: NULL];
    NSRect boundingRect = [[self layoutManager] boundingRectForGlyphRange: glyphRange inTextContainer: [self textContainer]];
    boundingRect = [self convertRect: boundingRect toView: NULL]; // convert to window and then to screen
    return [[self window] convertBaseToScreen: NSMakePoint(boundingRect.origin.x + boundingRect.size.width,boundingRect.origin.y + boundingRect.size.height / 2.0)];
}


- (void) popupMenuAtInsertion: (NSMenu *)menu
{
    [self popupMenuAtInsertion: menu size: 0]; // 0 will do default size
}

- (void) popupSmallMenuAtInsertion: (NSMenu *)menu
{
    [self popupMenuAtInsertion: menu size: [NSFont smallSystemFontSize]];
}

- (void) popupMenuAtInsertion: (NSMenu *)menu size: (float) size;
{
    NSEvent	    *theEvent= [NSEvent
							mouseEventWithType:NSLeftMouseDown
							location:[self insertionPointWindowCoordinate]
							modifierFlags:0
							timestamp:1
							windowNumber:[[NSApp mainWindow] windowNumber]
							context:[NSGraphicsContext currentContext]
							eventNumber:1
							clickCount:1
							pressure:0.0];
    if ([NSMenu respondsToSelector: @selector(popUpContextMenu:withEvent:forView:withFont:)])
		[NSMenu popUpContextMenu: menu withEvent: theEvent forView: self withFont: [NSFont menuFontOfSize:size]];
    else
		[NSMenu popUpContextMenu: menu withEvent: theEvent forView: self];
}

- (void) popupHelpTagAtInsertion: (NSAttributedString *)tagContent
{
    NSHelpManager *helpManager = [NSHelpManager sharedHelpManager];
    [helpManager setContextHelp: tagContent forObject: self];
    [helpManager showContextHelpForObject: self locationHint: [self insertionPointGlobalCoordinate]];
    [helpManager removeContextHelpForObject: self];
}

- (id) popupCompletionAtInsertion: (NSArray *)completionList
{
    IDEKit_Autocompletion *completer = [[IDEKit_Autocompletion alloc] initWithCompletions: completionList];
    id retval = [completer popupAssistantAt: [self insertionPointGlobalCoordinate] forView: self];
    return retval;
}
@end
