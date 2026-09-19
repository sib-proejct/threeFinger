#ifndef DockSwipe_h
#define DockSwipe_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Begins an interactive space swipe gesture (sends Phase Began).
void TMCDockSwipeBegin(void);

/// Updates the interactive space swipe gesture with incremental mouse deltaX (sends Phase Changed).
void TMCDockSwipeUpdate(double deltaX);

/// Ends the interactive space swipe gesture upon mouse release.
void TMCDockSwipeEnd(void);

/// Ends the interactive space swipe gesture with pointer release velocity.
void TMCDockSwipeEndWithVelocity(double velocityX);

/// Cancels the interactive space swipe gesture immediately (e.g. on Escape or tap abort).
void TMCDockSwipeCancel(void);

/// Returns YES if an interactive space swipe is currently in progress.
BOOL TMCDockSwipeIsActive(void);

NS_ASSUME_NONNULL_END

#endif /* DockSwipe_h */

