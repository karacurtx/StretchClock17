#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>

static const CGFloat ClockWidthScale = 1.22;
static const CGFloat ClockHeightScale = 1.65;
static const CGFloat SideMargin = 16.0;
static char AppliedTransformKey;

@protocol ClockViewAccess
- (UIView *)textLabel;
- (UIView *)timeLabel;
- (BOOL)usesEditingLayout;
@end

static UIView *clockLabel(UIView *owner, BOOL prominent) {
    id<ClockViewAccess> clock = (id<ClockViewAccess>)owner;
    SEL getter = prominent ? @selector(textLabel) : @selector(timeLabel);
    id candidate = nil;
    if ([owner respondsToSelector:getter]) {
        candidate = prominent ? [clock textLabel] : [clock timeLabel];
    }
    if (!candidate) {
        const char *name = prominent ? "_textLabel" : "_timeLabel";
        Ivar ivar = class_getInstanceVariable(object_getClass(owner), name);
        const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
        if (type && type[0] == '@') {
            candidate = object_getIvar(owner, ivar);
        }
    }
    if (![candidate isKindOfClass:[UIView class]] || candidate == owner) {
        return nil;
    }
    UIView *label = candidate;
    return [label isDescendantOfView:owner] ? label : nil;
}

static UIView *legacyClockLabel(UIView *owner) {
    UIView *label = clockLabel(owner, NO);
    Class prominent = objc_lookUpClass("CSProminentTimeView");
    for (UIView *view = label; view && view != owner; view = view.superview) {
        if (prominent && [view isKindOfClass:prominent]) return nil;
    }
    return label;
}

static void restoreClock(UIView *label) {
    if (!label) return;
    NSValue *applied = objc_getAssociatedObject(label, &AppliedTransformKey);
    if (!applied) return;

    if (CGAffineTransformEqualToTransform(label.transform, applied.CGAffineTransformValue)) {
        label.transform = CGAffineTransformIdentity;
    }
    objc_setAssociatedObject(label, &AppliedTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL isEditing(UIView *view) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if ([ancestor respondsToSelector:@selector(usesEditingLayout)] &&
            [(id<ClockViewAccess>)ancestor usesEditingLayout]) {
            return YES;
        }
        const char *name = class_getName(object_getClass(ancestor));
        if (strstr(name, "PosterEditing") || strstr(name, "PosterSwitcher") ||
            strstr(name, "PosterGallery")) {
            return YES;
        }
    }
    return NO;
}

static void stretchClock(UIView *label) {
    UIView *parent = label.superview;
    UIWindow *window = label.window;
    if (!parent || !window || label.hidden || isEditing(label) ||
        !CGAffineTransformIsIdentity(label.transform) ||
        !CGPointEqualToPoint(label.layer.anchorPoint, CGPointMake(0.5, 0.5))) {
        return;
    }

    CGRect box = label.frame;
    CGFloat width = CGRectGetWidth(box);
    CGFloat height = CGRectGetHeight(box);
    if (CGRectIsEmpty(box)) return;

    CGRect screen = CGRectInset(window.bounds, SideMargin, 0.0);
    CGRect available = [window convertRect:screen toView:parent];
    for (UIView *ancestor = parent; ancestor && ancestor != window; ancestor = ancestor.superview) {
        if (ancestor.clipsToBounds) {
            CGRect clip = [ancestor convertRect:ancestor.bounds toView:parent];
            available = CGRectIntersection(available, clip);
        }
    }
    if (CGRectIsEmpty(available)) return;

    CGFloat midX = CGRectGetMidX(box);
    CGFloat halfWidth = MIN(midX - CGRectGetMinX(available),
                            CGRectGetMaxX(available) - midX);
    CGFloat maxHeight = CGRectGetMaxY(available) - CGRectGetMinY(box);
    CGFloat sx = MAX(1.0, MIN(ClockWidthScale, 2.0 * halfWidth / width));
    CGFloat sy = MAX(1.0, MIN(ClockHeightScale, maxHeight / height));
    if (sx == 1.0 && sy == 1.0) return;

    // Keep the top of the clock in place as its text grows downward.
    CGAffineTransform transform = CGAffineTransformMake(sx, 0, 0, sy, 0,
                                                         (sy - 1.0) * height / 2.0);
    label.transform = transform;
    objc_setAssociatedObject(label, &AppliedTransformKey,
                             [NSValue valueWithCGAffineTransform:transform],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group ProminentClock
%hook CSProminentTimeView
- (void)layoutSubviews {
    UIView *clock = (UIView *)self;
    restoreClock(clockLabel(clock, YES));
    %orig;
    stretchClock(clockLabel(clock, YES));
}
%end
%end

%group LegacyClock
%hook SBFLockScreenDateView
- (void)layoutSubviews {
    UIView *clock = (UIView *)self;
    restoreClock(legacyClockLabel(clock));
    %orig;
    stretchClock(legacyClockLabel(clock));
}
%end
%end

%ctor {
    @autoreleasepool {
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 17) return;

        if (!objc_lookUpClass("CSProminentTimeView")) {
            dlopen("/System/Library/PrivateFrameworks/CoverSheetKit.framework/CoverSheetKit",
                   RTLD_LAZY | RTLD_LOCAL);
        }
        if (objc_lookUpClass("CSProminentTimeView")) {
            %init(ProminentClock);
        }
        if (objc_lookUpClass("SBFLockScreenDateView")) {
            %init(LegacyClock);
        }
    }
}
