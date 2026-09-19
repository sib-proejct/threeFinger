#ifndef DockSwipe_h
#define DockSwipe_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMCSpaceDirection) {
    TMCSpaceDirectionNext = 1,      // Swipe left -> Next space / full-screen app (desktop to the right)
    TMCSpaceDirectionPrevious = 2  // Swipe right -> Previous space / full-screen app (desktop to the left)
};

/// Begins an interactive space swipe gesture (sends Phase Began).
void TMCDockSwipeBegin(void);

/// Updates the interactive space swipe gesture with incremental mouse deltaX (sends Phase Changed).
void TMCDockSwipeUpdate(double deltaX);

/// Ends the interactive space swipe gesture upon mouse release.
void TMCDockSwipeEnd(void);

/// Ends the interactive space swipe gesture with pointer release velocity.
void TMCDockSwipeEndWithVelocity(double velocityX);

/// Commits the space swipe gesture immediately when the user swipes all the way across.
void TMCDockSwipeCommit(void);

/// Cancels the interactive space swipe gesture immediately (e.g. on Escape).
void TMCDockSwipeCancel(void);

/// Returns YES if an interactive space swipe is currently in progress.
BOOL TMCDockSwipeIsActive(void);

/// Synthesizes a one-shot native macOS trackpad DockSwipe gesture stream (Began -> Changed -> Ended).
void TMCTriggerSpaceSwipe(TMCSpaceDirection direction);

NS_ASSUME_NONNULL_END

#endif /* DockSwipe_h */

