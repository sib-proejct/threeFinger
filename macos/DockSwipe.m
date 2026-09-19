#import "DockSwipe.h"
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <math.h>
#import <unistd.h>
#import <string.h>

@interface MMFHIDEvent : NSObject
- (nullable instancetype)initWithType:(uint32_t)type
                            timestamp:(uint64_t)timestamp
                             senderID:(uint64_t)senderID;
- (void)setIntegerValue:(NSInteger)value forField:(uint32_t)field;
- (NSInteger)integerValueForField:(uint32_t)field;
- (void)setDoubleValue:(double)value forField:(uint32_t)field;
- (double)doubleValueForField:(uint32_t)field;
- (void)appendEvent:(MMFHIDEvent *)event;
@property uint32_t options;
@property (readonly) uint32_t type;
@property (readonly) uint64_t timestamp;
@end

typedef void (*SLEventSetIOHIDEventFn)(CGEventRef event, CFTypeRef hidEvent);

static SLEventSetIOHIDEventFn sSetHIDEvent = NULL;
static Class sHIDEventClass = Nil;
static dispatch_once_t sSkyLightInitOnce;

static void InitSkyLight(void) {
    dispatch_once(&sSkyLightInitOnce, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL);
        if (handle) {
            sSetHIDEvent = (SLEventSetIOHIDEventFn)dlsym(handle, "SLEventSetIOHIDEvent");
            sHIDEventClass = NSClassFromString(@"HIDEvent");
        }
    });
}

static void PostDockSwipeFrame(double offset, int motion, uint32_t phase, double exitSpeed) {
    @autoreleasepool {
        uint64_t now = mach_absolute_time();

        CGEventRef e30 = CGEventCreate(NULL);
        if (!e30) return;

        CGEventSetType(e30, (CGEventType)30); // kCGSEventDockControl / NSEventTypeMagnify
        CGEventSetTimestamp(e30, now);
        CGEventSetDoubleValueField(e30, (CGEventField)55, 30);
        CGEventSetDoubleValueField(e30, (CGEventField)110, 23); // kIOHIDEventTypeDockSwipe = 23
        CGEventSetDoubleValueField(e30, (CGEventField)123, (double)motion); // 1 = horizontal
        CGEventSetDoubleValueField(e30, (CGEventField)124, offset);
        CGEventSetDoubleValueField(e30, (CGEventField)132, phase);
        CGEventSetDoubleValueField(e30, (CGEventField)134, phase);

        Float32 ofsF = (Float32)offset;
        uint32_t ofsU;
        memcpy(&ofsU, &ofsF, sizeof(ofsF));
        CGEventSetIntegerValueField(e30, (CGEventField)135, (int64_t)ofsU);
        CGEventSetDoubleValueField(e30, (CGEventField)41, 33231);

        // IEEE-754 denormal representation of motion
        double wf = (motion == 1) ? 1.401298464324817e-45 : 2.802596928649634e-45;
        CGEventSetDoubleValueField(e30, (CGEventField)119, wf);
        CGEventSetDoubleValueField(e30, (CGEventField)139, wf);
        CGEventSetDoubleValueField(e30, (CGEventField)165, (double)motion);
        CGEventSetIntegerValueField(e30, (CGEventField)136, 0); // invertedFromDevice = NO

        if (phase == 4 || phase == 8) {
            CGEventSetDoubleValueField(e30, (CGEventField)129, exitSpeed);
            CGEventSetDoubleValueField(e30, (CGEventField)130, exitSpeed);
        }

        // On macOS 27+, WindowServer requires the HIDEvent payload attached via SkyLight
        if (sSetHIDEvent && sHIDEventClass) {
            MMFHIDEvent *hidEvent = [[sHIDEventClass alloc] initWithType:23 timestamp:now senderID:0];
            if (hidEvent) {
                hidEvent.options = phase << 24;
                [hidEvent setIntegerValue:motion forField:(23 << 16) | 1]; // Motion
                [hidEvent setIntegerValue:3 forField:(23 << 16) | 5]; // Flavor: DockPrimary
                [hidEvent setDoubleValue:offset forField:(23 << 16) | 2]; // Progress

                if (phase == 4 || phase == 8) {
                    MMFHIDEvent *velocity = [[sHIDEventClass alloc] initWithType:9 timestamp:now senderID:0];
                    if (velocity) {
                        [velocity setDoubleValue:exitSpeed forField:(9 << 16) | 0]; // VelocityX
                        [velocity setDoubleValue:exitSpeed forField:(9 << 16) | 1]; // VelocityY
                        [velocity setDoubleValue:0.0       forField:(9 << 16) | 2]; // VelocityZ
                        [hidEvent appendEvent:velocity];
                    }
                }
                sSetHIDEvent(e30, (__bridge CFTypeRef)hidEvent);
            }
        }

        CGEventPost(kCGSessionEventTap, e30);
        CFRelease(e30);
    }
}

static BOOL sIsSwiping = NO;
static double sCurrentOffset = 0.0;

static Boolean IsNaturalScrollEnabled(void) {
    Boolean keyExists = false;
    Boolean naturalScroll = CFPreferencesGetAppBooleanValue(
        CFSTR("com.apple.swipescrolldirection"),
        kCFPreferencesAnyApplication,
        &keyExists
    );
    return keyExists ? naturalScroll : true;
}

static double GetTravelDistance(void) {
    CGRect mainBounds = CGDisplayBounds(CGMainDisplayID());
    double screenWidth = mainBounds.size.width;
    if (screenWidth < 800.0) {
        screenWidth = 1440.0;
    }
    // Matching mouse speed to screen speed:
    // With 1 pixel of mouse travel = 1 pixel of screen travel,
    // screenWidth is the natural 1:1 scale (just like dragging a window).
    // On high-res screens (e.g. 2560px), a full screen width is 2560px.
    // With typical mouse acceleration, a comfortable hand swipe
    // across the desk covers about 500-700 points.
    // Setting travelDistance to screenWidth * 0.55 (e.g. ~1400 on 2560px, or ~830 on 1512px)
    // feels remarkably natural: the space moves at a 1:1 feel, neither sluggish
    // nor flying away.
    return screenWidth * 0.55;
}

static double ApplyRubberBand(double offset) {
    double absOffset = fabs(offset);
    if (absOffset <= 1.0) {
        return offset;
    }
    double excess = absOffset - 1.0;
    double damped = 1.0 + (excess * 0.15);
    if (damped > 1.05) damped = 1.05;
    return (offset < 0.0) ? -damped : damped;
}

void TMCDockSwipeBegin(void) {
    InitSkyLight();
    sIsSwiping = YES;
    sCurrentOffset = 0.0;
    PostDockSwipeFrame(0.0, 1, 1 /* Began */, 0.0);
}

void TMCDockSwipeUpdate(double deltaX) {
    if (!sIsSwiping) return;

    double travelDistance = GetTravelDistance();
    double step = deltaX / travelDistance;
    if (!IsNaturalScrollEnabled()) {
        step = -step;
    }

    sCurrentOffset += step;

    double bounded = ApplyRubberBand(sCurrentOffset);
    PostDockSwipeFrame(bounded, 1, 2 /* Changed */, 0.0);
}

void TMCDockSwipeEndWithVelocity(double velocityX) {
    if (!sIsSwiping) return;
    sIsSwiping = NO;

    double travelDistance = GetTravelDistance();
    double offsetVelocity = velocityX / travelDistance;
    if (!IsNaturalScrollEnabled()) {
        offsetVelocity = -offsetVelocity;
    }

    double startOffset = ApplyRubberBand(sCurrentOffset);
    uint32_t phase = 4; // Ended
    double exitSpeed = 0.0;

    // Strict speed limits to guarantee the screen never flies away like a rocket.
    // minSpeed ensures a clean, reliable glide into the target space.
    // maxSpeed caps the maximum speed to match gentle native trackpad glide.
    const double minSpeed = 1.4;
    const double maxSpeed = 2.6;

    // Must have at least 15% travel, or 8% travel with deliberate flick velocity
    if (startOffset <= -0.15 || (startOffset <= -0.08 && offsetVelocity < -0.4)) {
        phase = 4; // Ended -> Next Space
        double scaled = offsetVelocity * 2.5;
        if (scaled > -minSpeed) scaled = -minSpeed;
        if (scaled < -maxSpeed) scaled = -maxSpeed;
        exitSpeed = scaled;
    } else if (startOffset >= 0.15 || (startOffset >= 0.08 && offsetVelocity > 0.4)) {
        phase = 4; // Ended -> Previous Space
        double scaled = offsetVelocity * 2.5;
        if (scaled < minSpeed) scaled = minSpeed;
        if (scaled > maxSpeed) scaled = maxSpeed;
        exitSpeed = scaled;
    } else {
        phase = 8; // Cancelled -> return to current Space
        exitSpeed = 0.0;
    }

    PostDockSwipeFrame(startOffset, 1, phase, exitSpeed);
}

void TMCDockSwipeEnd(void) {
    TMCDockSwipeEndWithVelocity(0.0);
}

void TMCDockSwipeCancel(void) {
    if (!sIsSwiping) return;
    sIsSwiping = NO;

    double startOffset = ApplyRubberBand(sCurrentOffset);
    PostDockSwipeFrame(startOffset, 1, 8 /* Cancelled */, 0.0);
}

BOOL TMCDockSwipeIsActive(void) {
    return sIsSwiping;
}

