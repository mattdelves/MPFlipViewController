//
//  MPFlipTransition.m
//  MPTransition (v1.1.4)
//
//  Created by Mark Pospesel on 5/15/12.
//  Copyright (c) 2012 Mark Pospesel. All rights reserved.
//

#define DEFAULT_COVERED_PAGE_SHADOW_OPACITY	(1./3)
#define DEFAULT_FLIPPING_PAGE_SHADOW_OPACITY 0.1
#define DEFAULT_RUBBERBAND_MAX_PROGRESS (1./3)

#import "MPFlipTransition.h"
#import "MPAnimation.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#import <objc/runtime.h>

const char *MPassociatedCachedScreenshotLeftHalfKey = "MPassociatedCachedScreenshotLeftHalfKey";
const char *MPassociatedCachedScreenshotRightHalfKey = "MPassociatedCachedScreenshotRightHalfKey";

static inline double mp_radians (double degrees) {return degrees * M_PI/180;}

@interface MPFlipTransition()

@property (assign, nonatomic, getter = wasDestinationViewShown) BOOL destinationViewShown;
@property (assign, nonatomic, getter = wereLayersBuilt) BOOL layersBuilt;
@property (strong, nonatomic) UIView *animationView;
@property (strong, nonatomic) CALayer *layerFront;
@property (strong, nonatomic) CALayer *layerFacing;
@property (strong, nonatomic) CALayer *layerBack;
@property (strong, nonatomic) CALayer *layerReveal;
@property (strong, nonatomic) CAShapeLayer *revealLayerMask;
@property (strong, nonatomic) CAGradientLayer *layerFrontShadow;
@property (strong, nonatomic) CAGradientLayer *layerBackShadow;
@property (strong, nonatomic) CALayer *layerFacingShadow;
@property (strong, nonatomic) CALayer *layerRevealShadow;
@property (assign, nonatomic) MPFlipAnimationStage stage;
@property (weak, nonatomic) UIView *actingSource;
@property (assign, nonatomic) CGRect sourceFrame;

@end

@implementation MPFlipTransition

#pragma mark - Properties

@synthesize destinationViewShown = _destinationViewShown;
@synthesize layersBuilt = _layersBuilt;
@synthesize animationView = _animationView;
@synthesize layerFront = _layerFront;
@synthesize layerFacing = _layerFacing;
@synthesize layerBack = _layerBack;
@synthesize layerReveal = _layerReveal;
@synthesize revealLayerMask = _revealLayerMask;
@synthesize layerFrontShadow = _layerFrontShadow;
@synthesize layerBackShadow = _layerBackShadow;
@synthesize layerFacingShadow = _layerFacingShadow;
@synthesize layerRevealShadow = _layerRevealShadow;
@synthesize stage = _stage;
@synthesize actingSource = _actingSource;
@synthesize sourceFrame = _sourceFrame;

@synthesize style = _style;
@synthesize coveredPageShadowOpacity = _coveredPageShadowOpacity;
@synthesize flippingPageShadowOpacity = _flippingPageShadowOpacity;
@synthesize flipShadowColor = _flipShadowColor;
@synthesize rubberbandMaximumProgress = _rubberbandMaximumProgress;
@synthesize shouldRenderAllViews = _shouldRenderAllViews;

#pragma mark - init

- (id)initWithSourceView:(UIView *)sourceView destinationView:(UIView *)destinationView duration:(NSTimeInterval)duration style:(MPFlipStyle)style completionAction:(MPTransitionAction)action {
	self = [super initWithSourceView:sourceView destinationView:destinationView duration:duration timingCurve:UIViewAnimationCurveEaseInOut completionAction:action];
	if (self)
	{
		_style = style;	
		_coveredPageShadowOpacity = DEFAULT_COVERED_PAGE_SHADOW_OPACITY;
		_flippingPageShadowOpacity = DEFAULT_FLIPPING_PAGE_SHADOW_OPACITY;
		_flipShadowColor = [UIColor blackColor];
		_layersBuilt = NO;
		_stage = MPFlipAnimationStage1;
		_rubberbandMaximumProgress = DEFAULT_RUBBERBAND_MAX_PROGRESS;
		_shouldRenderAllViews = YES;
	}
	
	return self;
}

#pragma mark - Instance methods

// We split the animation into 2 parts, so don't ease out on the 1st half (we'll do that in 2nd half)
- (NSString *)timingCurveFunctionNameFirstHalf
{
	switch ([self timingCurve]) {
		case UIViewAnimationCurveEaseIn:
		case UIViewAnimationCurveEaseInOut:
			return kCAMediaTimingFunctionEaseIn;
			
		case UIViewAnimationCurveEaseOut:
		case UIViewAnimationCurveLinear:
			return kCAMediaTimingFunctionLinear;
	}
	
	return kCAMediaTimingFunctionEaseIn;
}

// We split the animation into 2 parts, so don't ease in on the 2nd half (we did that in the 1st half)
- (NSString *)timingCurveFunctionNameSecondHalf
{
	switch ([self timingCurve]) {
		case UIViewAnimationCurveEaseOut:
		case UIViewAnimationCurveEaseInOut:
			return kCAMediaTimingFunctionEaseOut;
			
		case UIViewAnimationCurveEaseIn:
		case UIViewAnimationCurveLinear:
			return kCAMediaTimingFunctionLinear;
	}
	
	return kCAMediaTimingFunctionEaseOut;
}

// switching between the 2 halves of the animation - between front and back sides of the page we're turning
- (void)switchToStage:(MPFlipAnimationStage)flipStage
{
	// 0 = stage 1, 1 = stage 2
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	if (flipStage == MPFlipAnimationStage1)
	{
		[self prepareForStage2];
		[self.animationView.layer insertSublayer:self.layerFacing above:self.layerReveal]; // re-order these 2 layers
		[self.animationView.layer insertSublayer:self.layerFront below:self.layerFacing];
		[self.layerReveal addSublayer:self.layerRevealShadow];
		
		[self.layerBack removeFromSuperlayer];
		[self.layerFacingShadow removeFromSuperlayer];
	}
	else
	{
		[self doFlip1:1];
		[self.animationView.layer insertSublayer:self.layerReveal above:self.layerFacing]; // re-order these 2 layers
		[self.animationView.layer insertSublayer:self.layerBack below:self.layerReveal];
		[self.layerFacing addSublayer:self.layerFacingShadow];
		
		[self.layerFront removeFromSuperlayer];
		[self.layerRevealShadow removeFromSuperlayer];
	}
	
	[CATransaction commit];
}

- (void)buildLayers
{
	[self buildLayers:NO];
}

- (void)buildLayers:(BOOL)isResizing
{
	if (!isResizing && [self wereLayersBuilt])
		return;

	BOOL forwards = ([self style] & MPFlipStyleDirectionMask) != MPFlipStyleDirectionBackward;
	BOOL vertical = ([self style] & MPFlipStyleOrientationMask) == MPFlipStyleOrientationVertical;
	BOOL inward = ([self style] & MPFlipStylePerspectiveMask) == MPFlipStylePerspectiveReverse;
	BOOL isRubberbanding = !self.destinationView;
	
	CGRect bounds = self.rect;
	CGFloat scale = [[UIScreen mainScreen] scale];
	
	// we inset the panels 1 point on each side with a transparent margin to antialiase the edges
	UIEdgeInsets insets = vertical? UIEdgeInsetsMake(0, 1, 0, 1) : UIEdgeInsetsMake(1, 0, 1, 0);
	
	CGRect upperRect = bounds;
	if (vertical)
		upperRect.size.height = bounds.size.height / 2;
	else
		upperRect.size.width = bounds.size.width / 2;
	CGRect lowerRect = upperRect;
	BOOL isOddSize = vertical? (upperRect.size.height != (roundf(upperRect.size.height * scale)/scale)) : (upperRect.size.width != (roundf(upperRect.size.width * scale) / scale));
	if (isOddSize)
	{
		// If view has an odd height, make the 2 panels of integer height with top panel 1 pixel taller (see below)
		if (vertical)
		{
			upperRect.size.height = (roundf(upperRect.size.height * scale)/scale);
			lowerRect.size.height = bounds.size.height - upperRect.size.height;
		}
		else 
		{
			upperRect.size.width = (roundf(upperRect.size.width * scale)/scale);
			lowerRect.size.width = bounds.size.width - upperRect.size.width;
		}
	}
	if (vertical)
		lowerRect.origin.y += upperRect.size.height;
	else
		lowerRect.origin.x += upperRect.size.width;
	
	if (![self isDimissing] && !isRubberbanding)
		self.destinationView.bounds = (CGRect){CGPointZero, bounds.size};
	
	CGRect destUpperRect = CGRectOffset(upperRect, -upperRect.origin.x, -upperRect.origin.y);
	CGRect destLowerRect = CGRectOffset(lowerRect, -upperRect.origin.x, -upperRect.origin.y);
	
	if ([self isDimissing] && !isRubberbanding)
	{
		CGFloat x = self.destinationView.bounds.size.width - bounds.size.width;
		CGFloat y = self.destinationView.bounds.size.height - bounds.size.height;
		destUpperRect.origin.x += x;
		destLowerRect.origin.x += x;
		destUpperRect.origin.y += y;
		destLowerRect.origin.y += y;
		[self setRect:CGRectOffset([self rect], x, y)];
	}
	
	// Create 4 images to represent 2 halves of the 2 views
	
	// The page flip animation is broken into 2 halves
	// 1. Flip old page up to vertical
	// 2. Flip new page from vertical down to flat
	// as we pass the halfway point of the animation, the "page" switches from old to new
	
	// front Page  = the half of current view we are flipping during 1st half
	// facing Page = the other half of the current view (doesn't move, gets covered by back page during 2nd half)
	// back Page   = the half of the next view that appears on the flipping page during 2nd half
	// reveal Page = the other half of the next view (doesn't move, gets revealed by front page during 1st half)
    UIImage *pageFrontImage = [self preCachedImageFromView:self.sourceView onSide:forwards];

    if (!pageFrontImage)
    {
        pageFrontImage = [MPAnimation renderImageFromView:self.sourceView withRect:forwards? lowerRect : upperRect transparentInsets:insets];
    }

	self.actingSource = [self sourceView]; // the view that is already part of the view hierarchy
	UIView *containerView = [self.actingSource superview];
	if (!containerView && !isRubberbanding)
	{
		// in case of dismissal, it is actually the destination view since we had to add it
		// in order to get it to render correctly
		self.actingSource = [self destinationView];
		containerView = [self.actingSource superview];
	}
	
	if (!isResizing)
	{
		[self.actingSource addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
		self.sourceFrame = [self.actingSource frame];
	}
	
	BOOL isDestinationViewAbove = !isRubberbanding;
	BOOL isModal = [containerView isKindOfClass:[UIWindow class]];
	BOOL drawFacing = [self shouldRenderAllViews], drawReveal = [self shouldRenderAllViews];
	
	switch (self.completionAction)
	{
		case MPTransitionActionAddRemove:
			if (!isModal && !isRubberbanding)
				[self.destinationView setFrame:[self.sourceView frame]];
			if (!isRubberbanding && !isResizing)
				[containerView addSubview:self.destinationView];
			break;
			
		case MPTransitionActionShowHide:
			[self.destinationView setHidden:NO];
			isDestinationViewAbove = isRubberbanding? NO : [self.destinationView isAboveSiblingView:self.sourceView];
			break;
			
		case MPTransitionActionNone:
			if ([self.destinationView superview] == [self.sourceView superview])
			{
				isDestinationViewAbove = [self.destinationView isAboveSiblingView:self.sourceView];
				if ([self.destinationView isHidden])
				{
					[self.destinationView setHidden:NO];
					[self setDestinationViewShown:YES];
				}
			}
			else if (![self.sourceView superview])
			{
				drawFacing = YES;
			}
			else
			{
				drawReveal = !isRubberbanding;
				if ([self.destinationView isHidden])
				{
					[self.destinationView setHidden:NO];
					[self setDestinationViewShown:YES];
				}
			}
			break;
	}

    UIImage *pageFacingImage = nil;

    if (drawFacing) {
        pageFacingImage = [self preCachedImageFromView:self.sourceView onSide:!forwards];

        if (!pageFacingImage)
        {
            pageFacingImage = [MPAnimation renderImageFromView:self.sourceView withRect:forwards? upperRect : lowerRect];
        }
    }
	
    UIImage *pageBackImage = nil;

    if (!isRubberbanding) {
        pageBackImage = [self preCachedImageFromView:self.destinationView onSide:!forwards];

        if (!pageBackImage)
        {
            pageBackImage = [MPAnimation renderImageFromView:self.destinationView withRect:forwards? destUpperRect : destLowerRect transparentInsets:insets];
        }
    }

    UIImage *pageRevealImage = nil;

    if (drawReveal) {
        pageRevealImage = [self preCachedImageFromView:self.destinationView onSide:forwards];

        if (!pageRevealImage)
        {
            pageRevealImage = [MPAnimation renderImageFromView:self.destinationView withRect:forwards? destLowerRect : destUpperRect];
        }
    }

	CATransform3D transform = CATransform3DIdentity;
	
	CGFloat width = vertical? bounds.size.width : bounds.size.height;
	CGFloat height = vertical? bounds.size.height/2 : bounds.size.width/2;
	CGFloat upperHeight = roundf(height * scale) / scale; // round heights to integer for odd height
	
	// view to hold all our sublayers
	CGRect mainRect = [containerView convertRect:self.rect fromView:self.actingSource];
	CGPoint center = (CGPoint){CGRectGetMidX(mainRect), CGRectGetMidY(mainRect)};
	if (isModal)
		mainRect = [self.actingSource convertRect:mainRect fromView:nil];
	if (!isResizing)
		self.animationView = [[UIView alloc] initWithFrame:mainRect];
	else
		self.animationView.frame = mainRect;
	self.animationView.backgroundColor = [UIColor clearColor];
	self.animationView.transform = self.actingSource.transform;
	self.animationView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
	if (!isResizing)
		[containerView addSubview:self.animationView];
	if (isModal)
	{
		[self.animationView.layer setPosition:center];
	}
	
	if (!isRubberbanding)
	{
		if (!isResizing)
			self.layerReveal = [CALayer layer];
		self.layerReveal.bounds = (CGRect){CGPointZero, drawReveal? pageRevealImage.size : forwards? destLowerRect.size : destUpperRect.size};
		self.layerReveal.anchorPoint = CGPointMake(vertical? 0.5 : forwards? 0 : 1, vertical? forwards? 0 : 1 : 0.5);
		self.layerReveal.position = CGPointMake(vertical? width/2 : upperHeight, vertical? upperHeight : width/2);
		if (drawReveal)
			[self.layerReveal setContents:(id)[pageRevealImage CGImage]];
		if (!isResizing)
			[self.animationView.layer addSublayer:self.layerReveal];
	}
	
	if (!isResizing)
		self.layerFacing = [CALayer layer];
	self.layerFacing.bounds = (CGRect){CGPointZero, drawFacing? pageFacingImage.size : forwards? upperRect.size : lowerRect.size};
	self.layerFacing.anchorPoint = CGPointMake(vertical? 0.5 : forwards? 1 : 0, vertical? forwards? 1 : 0 : 0.5);
	self.layerFacing.position = CGPointMake(vertical? width/2 : upperHeight, vertical? upperHeight : width/2);
	if (drawFacing)
		[self.layerFacing setContents:(id)[pageFacingImage CGImage]];
	if (!isResizing)
		[self.animationView.layer addSublayer:self.layerFacing];
	
	if (![self shouldRenderAllViews] || isRubberbanding)
	{
		if (!isResizing)
			self.revealLayerMask = [CAShapeLayer layer];
		CGRect maskRect = (forwards == isDestinationViewAbove)? destLowerRect : destUpperRect;
		self.revealLayerMask.path = [[UIBezierPath bezierPathWithRect:maskRect] CGPath];
		UIView *viewToMask = isDestinationViewAbove? self.destinationView : self.sourceView;
		[viewToMask.layer setMask:self.revealLayerMask];
	}
	
	if (!isResizing)
		self.layerFront = [CALayer layer];
	self.layerFront.bounds = (CGRect){CGPointZero, pageFrontImage.size};
	self.layerFront.anchorPoint = CGPointMake(vertical? 0.5 : forwards? 0 : 1, vertical? forwards? 0 : 1 : 0.5);
	self.layerFront.position = CGPointMake(vertical? width/2 : upperHeight, vertical? upperHeight : width/2);
	[self.layerFront setContents:(id)[pageFrontImage CGImage]];
	if (!isResizing)
		[self.animationView.layer addSublayer:self.layerFront];
	
	if (!isRubberbanding)
	{
		if (!isResizing)
			self.layerBack = [CALayer layer];
		self.layerBack.bounds = (CGRect){CGPointZero, pageBackImage.size};
		self.layerBack.anchorPoint = CGPointMake(vertical? 0.5 : forwards? 1 : 0, vertical? forwards? 1 : 0 : 0.5);
		self.layerBack.position = CGPointMake(vertical? width/2 : upperHeight, vertical? upperHeight : width/2);
		[self.layerBack setContents:(id)[pageBackImage CGImage]];
	}
	
	// Create shadow layers
	if (!isResizing)
	{
		self.layerFrontShadow = [CAGradientLayer layer];
		[self.layerFront addSublayer:self.layerFrontShadow];
		self.layerFrontShadow.opacity = 0.0;
		if (forwards)
			self.layerFrontShadow.colors = [NSArray arrayWithObjects:(id)[[[self flipShadowColor] colorWithAlphaComponent:0.5] CGColor], (id)[self flipShadowColor].CGColor, (id)[[UIColor clearColor] CGColor], nil];
		else
			self.layerFrontShadow.colors = [NSArray arrayWithObjects:(id)[[UIColor clearColor] CGColor], (id)[self flipShadowColor].CGColor, (id)[[[self flipShadowColor] colorWithAlphaComponent:0.5] CGColor], nil];
		self.layerFrontShadow.startPoint = CGPointMake(vertical? 0.5 : forwards? 0 : 0.5, vertical? forwards? 0 : 0.5 : 0.5);
		self.layerFrontShadow.endPoint = CGPointMake(vertical? 0.5 : forwards? 0.5 : 1, vertical? forwards? 0.5 : 1 : 0.5);
		self.layerFrontShadow.locations = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:forwards? 0.1 : 0.9], [NSNumber numberWithDouble:1], nil];
	}
	self.layerFrontShadow.frame = CGRectInset(self.layerFront.bounds, insets.left, insets.top);
	
	if (!isRubberbanding)
	{
		if (!isResizing)
		{
			self.layerBackShadow = [CAGradientLayer layer];
			[self.layerBack addSublayer:self.layerBackShadow];
			self.layerBackShadow.opacity = [self flippingPageShadowOpacity];
			if (forwards)
				self.layerBackShadow.colors = [NSArray arrayWithObjects:(id)[[UIColor clearColor] CGColor], (id)[self flipShadowColor].CGColor, (id)[[[self flipShadowColor] colorWithAlphaComponent:0.5] CGColor], nil];
			else
				self.layerBackShadow.colors = [NSArray arrayWithObjects:(id)[[[self flipShadowColor] colorWithAlphaComponent:0.5] CGColor], (id)[self flipShadowColor].CGColor, (id)[[UIColor clearColor] CGColor], nil];
			self.layerBackShadow.startPoint = CGPointMake(vertical? 0.5 : forwards? 0.5 : 0, vertical? forwards? 0.5 : 0 : 0.5);
			self.layerBackShadow.endPoint = CGPointMake(vertical? 0.5 : forwards? 1 : 0.5, vertical? forwards? 1 : 0.5 : 0.5);
			self.layerBackShadow.locations = [NSArray arrayWithObjects:[NSNumber numberWithDouble:0], [NSNumber numberWithDouble:forwards? 0.9 : 0.1], [NSNumber numberWithDouble:1], nil];
		}
		self.layerBackShadow.frame = CGRectInset(self.layerBack.bounds, insets.left, insets.top);
	}
	
	if (!inward)
	{
		if (!isRubberbanding)
		{
			if (!isResizing)
			{
				self.layerRevealShadow = [CALayer layer];
				[self.layerReveal addSublayer:self.layerRevealShadow];
				self.layerRevealShadow.backgroundColor = [self flipShadowColor].CGColor;
				self.layerRevealShadow.opacity = [self coveredPageShadowOpacity];
			}
			self.layerRevealShadow.frame = self.layerReveal.bounds;
		}
		
		if (!isResizing)
		{
			self.layerFacingShadow = [CALayer layer];
			//[self.layerFacing addSublayer:self.layerFacingShadow]; // add later
			self.layerFacingShadow.backgroundColor = [self flipShadowColor].CGColor;
			self.layerFacingShadow.opacity = 0.0;
		}
		self.layerFacingShadow.frame = self.layerFacing.bounds;
	}
	
	// Perspective is best proportional to the height of the pieces being folded away, rather than a fixed value
	// the larger the piece being folded, the more perspective distance (zDistance) is needed.
	// m34 = -1/zDistance
	if ([self m34] == INFINITY)
		transform.m34 = -1.0/(height * 4.6666667);
	else
		transform.m34 = [self m34];
	if (inward)
		transform.m34 = -transform.m34; // flip perspective around
	self.animationView.layer.sublayerTransform = transform;
		
	[self setLayersBuilt:YES];
}

- (UIImage *)preCachedImageFromView:(UIView *)view onSide:(BOOL)right {
    UIImage * image = (UIImage *)objc_getAssociatedObject(view, right? MPassociatedCachedScreenshotRightHalfKey : MPassociatedCachedScreenshotLeftHalfKey);
    if (image) {
        NSLog(@"Pre-cached image for %@ found (%@ side)", view, right? @"right" : @"left");
    }

    return image;
}

- (void)cleanupLayers
{
	// cleanup
	if (![self wereLayersBuilt])
		return;
	
	[self.animationView removeFromSuperview];

	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	[self.revealLayerMask removeFromSuperlayer]; // don't animate
	[CATransaction commit];

	self.animationView = nil;
	self.layerFront = nil;
	self.layerBack = nil;
	self.layerFacing = nil;
	self.layerReveal = nil;
	self.layerFrontShadow = nil;
	self.layerBackShadow = nil;
	self.layerFacingShadow = nil;
	self.layerRevealShadow = nil;
	self.revealLayerMask = nil;
	
	[self.actingSource removeObserver:self forKeyPath:@"frame"];
	self.actingSource = nil;
	
	[self setLayersBuilt:NO];
}

- (void)perform:(void (^)(BOOL finished))completion
{
	[self buildLayers];
	[self prepareForStage2]; // set back page to vertical
	[self animateFlip1:NO fromProgress:0 withCompletion:completion];
}

- (void)performRubberband:(void (^)(BOOL finished))completion
{
	[self buildLayers];
	CGFloat maxProgress = [self rubberbandMaximumProgress];
	[self setDuration:[self duration] * 1 / maxProgress]; // necessary to arrive at the dersired total duration
	[self animateFlip1:NO fromProgress:0 toProgress:maxProgress withCompletion:^(BOOL finished) {
		[self animateFlip1:YES fromProgress:maxProgress toProgress:0 withCompletion:^(BOOL finished) {
			[self cleanupLayers];
			[self transitionDidComplete:NO];
			
			if (completion)
				completion(finished); // execute the completion block that was passed in
		}];
	}];
}

- (void)animateFlip1:(BOOL)isFallingBack fromProgress:(CGFloat)fromProgress withCompletion:(void (^)(BOOL finished))completion
{
	[self animateFlip1:isFallingBack fromProgress:fromProgress toProgress:1.0 withCompletion:completion];
}

- (void)animateFlip1:(BOOL)isFallingBack fromProgress:(CGFloat)fromProgress toProgress:(CGFloat)toProgress withCompletion:(void (^)(BOOL finished))completion
{
	BOOL forwards = ([self style] & MPFlipStyleDirectionMask) != MPFlipStyleDirectionBackward;
	BOOL vertical = ([self style] & MPFlipStyleOrientationMask) == MPFlipStyleOrientationVertical;
	BOOL inward = ([self style] & MPFlipStylePerspectiveMask) == MPFlipStylePerspectiveReverse;
	BOOL isRubberbanding = !self.destinationView;
	
	// 2-stage animation
	CALayer *layer = isFallingBack && !isRubberbanding? self.layerBack : self.layerFront;
	CALayer *flippingShadow = isFallingBack && !isRubberbanding? self.layerBackShadow : self.layerFrontShadow;
	CALayer *coveredShadow = isFallingBack && !isRubberbanding? self.layerFacingShadow : self.layerRevealShadow;
	
	if (isFallingBack && !isRubberbanding)
		fromProgress = 1 - fromProgress;
	
	// Figure out how many frames we want
	CGFloat duration = (self.duration / 2) * fabsf(toProgress - fromProgress);
	NSUInteger frameCount = ceilf(duration * 60); // Let's shoot for 60 FPS to ensure proper sine curve approximation
	
	NSString *rotationKey = vertical? @"transform.rotation.x" : @"transform.rotation.y";
	double factor = (isFallingBack && !isRubberbanding? -1 : 1) * (forwards? -1 : 1) * (vertical? -1 : 1) * M_PI / 180;
	CGFloat coveredPageShadowOpacity = [self coveredPageShadowOpacity];
	
	// Create a transaction
	[CATransaction begin];
	[CATransaction setValue:[NSNumber numberWithFloat:duration] forKey:kCATransactionAnimationDuration];
	[CATransaction setValue:[CAMediaTimingFunction functionWithName:isRubberbanding? kCAMediaTimingFunctionEaseInEaseOut : fromProgress > 0? kCAMediaTimingFunctionLinear : [self timingCurveFunctionNameFirstHalf]] forKey:kCATransactionAnimationTimingFunction];
	[CATransaction setCompletionBlock:^{
		// 2nd half of animation, once 1st half completes
		if (toProgress == 1)
		{
			[self setStage:isFallingBack? MPFlipAnimationStage1 : MPFlipAnimationStage2];
			[self switchToStage:isFallingBack? MPFlipAnimationStage1 : MPFlipAnimationStage2];
			
			[self animateFlip2:isFallingBack fromProgress:isFallingBack? 1 : 0 withCompletion:completion];
		}
		else
		{
			if (completion)
				completion(YES);
		}
	}];
	
	// First Half of Animation
	
	// Flip front page from flat up to vertical
	CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:rotationKey];
	[animation setFromValue:[NSNumber numberWithDouble:90 * factor * fromProgress]];
	[animation setToValue:[NSNumber numberWithDouble:90 * factor * toProgress]];
	[animation setFillMode:kCAFillModeForwards];
	[animation setRemovedOnCompletion:NO];
	[layer addAnimation:animation forKey:nil];
	[layer setTransform:CATransform3DMakeRotation(90*factor*toProgress, vertical? 1 : 0, vertical? 0 : 1, 0)];
	
	// Shadows
	
	// darken front page just slightly as we flip (just to give it a crease where it touches facing page)
	animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
	[animation setFromValue:[NSNumber numberWithDouble:[self flippingPageShadowOpacity] * fromProgress]];
	[animation setToValue:[NSNumber numberWithDouble:[self flippingPageShadowOpacity] * toProgress]];
	[animation setFillMode:kCAFillModeForwards];
	[animation setRemovedOnCompletion:NO];
	[flippingShadow addAnimation:animation forKey:nil];
	[flippingShadow setOpacity:[self flippingPageShadowOpacity] * toProgress];
	
	if (!inward && !isRubberbanding)
	{
		// lighten the page that is revealed by front page flipping up (along a cosine curve)
		// TODO: consider FROM value
		NSMutableArray* arrayOpacity = [NSMutableArray arrayWithCapacity:frameCount + 1];
		CGFloat progress;
		CGFloat cosOpacity;
		for (int frame = 0; frame <= frameCount; frame++)
		{
			progress = fromProgress + (toProgress - fromProgress) * ((float)frame) / frameCount;
			cosOpacity = cos(mp_radians(90 * progress)) * coveredPageShadowOpacity;
			if (frame == frameCount)
				cosOpacity = 0;
			[arrayOpacity addObject:[NSNumber numberWithFloat:cosOpacity]];
		}
		
		CAKeyframeAnimation *keyAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
		[keyAnimation setValues:[NSArray arrayWithArray:arrayOpacity]];
		[keyAnimation setFillMode:kCAFillModeForwards];
		[keyAnimation setRemovedOnCompletion:NO];
		[coveredShadow addAnimation:keyAnimation forKey:nil];
		[coveredShadow setOpacity:[[arrayOpacity lastObject] floatValue]];
	}
		
	// Commit the transaction for 1st half
	[CATransaction commit];
}

- (void)animateFlip2:(BOOL)isFallingBack fromProgress:(CGFloat)fromProgress withCompletion:(void (^)(BOOL finished))completion
{
	// Second half of animation
	BOOL forwards = ([self style] & MPFlipStyleDirectionMask) != MPFlipStyleDirectionBackward;
	BOOL vertical = ([self style] & MPFlipStyleOrientationMask) == MPFlipStyleOrientationVertical;
	BOOL inward = ([self style] & MPFlipStylePerspectiveMask) == MPFlipStylePerspectiveReverse;

	// 1-stage animation
	CALayer *layer = isFallingBack? self.layerFront : self.layerBack;
	CALayer *flippingShadow = isFallingBack? self.layerFrontShadow : self.layerBackShadow;
	CALayer *coveredShadow = isFallingBack? self.layerRevealShadow : self.layerFacingShadow;
	
	NSUInteger frameCount = ceilf((self.duration / 2) * 60); // Let's shoot for 60 FPS to ensure proper sine curve approximation
	
	NSString *rotationKey = vertical? @"transform.rotation.x" : @"transform.rotation.y";
	double factor = (isFallingBack? -1 : 1) * (forwards? -1 : 1) * (vertical? -1 : 1) * M_PI / 180;
	CGFloat coveredPageShadowOpacity = [self coveredPageShadowOpacity];
	
	if (isFallingBack)
		fromProgress = 1 - fromProgress;
	CGFloat toProgress = 1;
	
	// Create a transaction
	[CATransaction begin];
	[CATransaction setValue:[NSNumber numberWithFloat:self.duration/2] forKey:kCATransactionAnimationDuration];
	[CATransaction setValue:[CAMediaTimingFunction functionWithName:[self timingCurveFunctionNameSecondHalf]] forKey:kCATransactionAnimationTimingFunction];
	[CATransaction setCompletionBlock:^{
		// This is the final completion block, when 2nd half of animation finishes
		[self cleanupLayers];
		[self transitionDidComplete:!isFallingBack];
		
		if (completion)
			completion(YES); // execute the completion block that was passed in
	}];
	
	// Flip back page from vertical down to flat
	CABasicAnimation* animation2 = [CABasicAnimation animationWithKeyPath:rotationKey];
	[animation2 setFromValue:[NSNumber numberWithDouble:-90*factor*(1-fromProgress)]];
	[animation2 setToValue:[NSNumber numberWithDouble:0]];
	[animation2 setFillMode:kCAFillModeForwards];
	[animation2 setRemovedOnCompletion:NO];
	[layer addAnimation:animation2 forKey:nil];
	[layer setTransform:CATransform3DIdentity];
	
	// Shadows
	
	// Lighten back page just slightly as we flip (just to give it a crease where it touches reveal page)
	animation2 = [CABasicAnimation animationWithKeyPath:@"opacity"];
	[animation2 setFromValue:[NSNumber numberWithDouble:[self flippingPageShadowOpacity] * (1-fromProgress)]];
	[animation2 setToValue:[NSNumber numberWithDouble:0]];
	[animation2 setFillMode:kCAFillModeForwards];
	[animation2 setRemovedOnCompletion:NO];
	[flippingShadow addAnimation:animation2 forKey:nil];
	[flippingShadow setOpacity:0];
	
	if (!inward)
	{
		// Darken facing page as it gets covered by back page flipping down (along a sine curve)
		NSMutableArray* arrayOpacity = [NSMutableArray arrayWithCapacity:frameCount + 1];
		CGFloat progress;
		CGFloat sinOpacity;
		for (int frame = 0; frame <= frameCount; frame++)
		{
			progress = fromProgress + (toProgress - fromProgress) * ((float)frame) / frameCount;
			sinOpacity = (sin(mp_radians(90 * progress))* coveredPageShadowOpacity);
			if (frame == 0)
				sinOpacity = 0;
			[arrayOpacity addObject:[NSNumber numberWithFloat:sinOpacity]];
		}
		
		CAKeyframeAnimation *keyAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
		[keyAnimation setValues:[NSArray arrayWithArray:arrayOpacity]];
		[keyAnimation setFillMode:kCAFillModeForwards];
		[keyAnimation setRemovedOnCompletion:NO];
		[coveredShadow addAnimation:keyAnimation forKey:nil];
		[coveredShadow setOpacity:[[arrayOpacity lastObject] floatValue]];
	}
	
	// Commit the transaction for 2nd half
	[CATransaction commit];
}

// set view to any position within either half of the animation
// progress ranges from 0 (start) to 1 (complete) within each of 2 animation stages
- (void)setStage:(MPFlipAnimationStage)stage progress:(CGFloat)progress
{
	if ([self stage] != stage)
	{
		[self setStage:stage];
		[self switchToStage:stage];
	}
	
	if (stage == MPFlipAnimationStage1)
		[self doFlip1:progress];
	else
		[self doFlip2:progress];
}

// moves layers into position for beginning of stage 2 (flip back page to vertical)
- (void)prepareForStage2
{
	[self doFlip2:0];
}

// set view to any position within the 1st half of the animation
// progress ranges from 0 (start) to 1 (complete)
- (void)doFlip1:(CGFloat)progress
{
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	if (progress < 0)
		progress = 0;
	else if (progress > 1)
		progress = 1;
	
	[self.layerFront setTransform:[self flipTransform1:progress]];
	[self.layerFrontShadow setOpacity:[self flippingPageShadowOpacity] * progress];
	CGFloat cosOpacity = cos(mp_radians(90 * progress)) * [self coveredPageShadowOpacity];
	[self.layerRevealShadow setOpacity:cosOpacity];
	
	[CATransaction commit];
}

// set view to any position within the 2nd half of the animation
// progress ranges from 0 (start) to 1 (complete)
- (void)doFlip2:(CGFloat)progress
{
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	if (progress < 0)
		progress = 0;
	else if (progress > 1)
		progress = 1;
	
	[self.layerBack setTransform:[self flipTransform2:progress]];
	[self.layerBackShadow setOpacity:[self flippingPageShadowOpacity] * (1- progress)];
	CGFloat sinOpacity = sin(mp_radians(90 * progress)) * [self coveredPageShadowOpacity];
	[self.layerFacingShadow setOpacity:sinOpacity];
		
	[CATransaction commit];
}

// fetch the flipping page transform for any position within the 1st half of the animation
// progress ranges from 0 (start) to 1 (complete)
- (CATransform3D)flipTransform1:(CGFloat)progress
{
	CATransform3D tHalf1 = CATransform3DIdentity;
	
	// rotate away from viewer
	BOOL forwards = ([self style] & MPFlipStyleDirectionMask) != MPFlipStyleDirectionBackward;
	BOOL vertical = ([self style] & MPFlipStyleOrientationMask) == MPFlipStyleOrientationVertical;
	tHalf1 = CATransform3DRotate(tHalf1, mp_radians(90 * progress * (forwards? -1 : 1)), vertical? -1 : 0, vertical? 0 : 1, 0);
	
	return tHalf1;
}

// fetch the flipping page transform for any position within the 2nd half of the animation
// progress ranges from 0 (start) to 1 (complete)
- (CATransform3D)flipTransform2:(CGFloat)progress
{
	CATransform3D tHalf2 = CATransform3DIdentity;
	
	// rotate away from viewer
	BOOL forwards = ([self style] & MPFlipStyleDirectionMask) != MPFlipStyleDirectionBackward;
	BOOL vertical = ([self style] & MPFlipStyleOrientationMask) == MPFlipStyleOrientationVertical;
	tHalf2 = CATransform3DRotate(tHalf2, mp_radians(90 * (1 - progress)) * (forwards? 1 : -1), vertical? -1 : 0, vertical? 0 : 1, 0);
	
	return tHalf2;
}

- (void)animateFromProgress:(CGFloat)fromProgress shouldFallBack:(BOOL)shouldFallBack completion:(void (^)(BOOL finished))completion
{
	BOOL isFrontPage = [self stage] == MPFlipAnimationStage1;
	if (shouldFallBack == isFrontPage) {
		// we're either on 1st page falling back, or on 2nd page falling forward - simple 1 stage animation
		[self animateFlip2:shouldFallBack fromProgress:fromProgress withCompletion:completion];
	}
	else
	{
		// we're either on 1st page flipping forward or on 2nd page flipping back - 2 stage animation
		[self animateFlip1:shouldFallBack fromProgress:fromProgress withCompletion:completion];
	}
}

- (void)transitionDidComplete
{
	[self transitionDidComplete:YES];
}

- (void)transitionDidComplete:(BOOL)completed
{
	if (completed)
	{
		switch (self.completionAction) {
			case MPTransitionActionAddRemove:
				[self.sourceView removeFromSuperview];
				break;
				
			case MPTransitionActionShowHide:
				[self.sourceView setHidden:YES];
				break;
				
			case MPTransitionActionNone:
				// undo whatever actions we took during animation
				if ([self wasDestinationViewShown])
					[self.destinationView setHidden:YES];
				break;
		}
	}
	else {
		switch (self.completionAction) {
			case MPTransitionActionAddRemove:
				[self.destinationView removeFromSuperview];
				break;
				
			case MPTransitionActionShowHide:
				[self.destinationView setHidden:YES];
				break;
				
			case MPTransitionActionNone:
				// undo whatever actions we took during animation
				if ([self wasDestinationViewShown])
					[self.destinationView setHidden:YES];
				break;
		}
	}
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"frame"])
	{
		if (!CGRectEqualToRect(self.sourceFrame, [self.actingSource frame]))
		{
			self.rect = self.sourceView.bounds;
			[self buildLayers:YES];
			self.sourceFrame = [self.actingSource frame];
		}
	}
}

#pragma mark - Class methods

+ (void)transitionFromViewController:(UIViewController *)fromController toViewController:(UIViewController *)toController duration:(NSTimeInterval)duration style:(MPFlipStyle)style completion:(void (^)(BOOL finished))completion
{
	MPFlipTransition *flipTransition = [[MPFlipTransition alloc] initWithSourceView:fromController.view destinationView:toController.view duration:duration style:style completionAction:MPTransitionActionNone];
	[flipTransition perform:completion];
}

+ (void)transitionFromView:(UIView *)fromView toView:(UIView *)toView duration:(NSTimeInterval)duration style:(MPFlipStyle)style transitionAction:(MPTransitionAction)action completion:(void (^)(BOOL finished))completion
{
	MPFlipTransition *flipTransition = [[MPFlipTransition alloc] initWithSourceView:fromView destinationView:toView duration:duration style:style completionAction:action];
	[flipTransition perform:completion];
}

+ (void)presentViewController:(UIViewController *)viewControllerToPresent from:(UIViewController *)presentingController duration:(NSTimeInterval)duration style:(MPFlipStyle)style completion:(void (^)(BOOL finished))completion
{		
	MPFlipTransition *flipTransition = [[MPFlipTransition alloc] initWithSourceView:presentingController.view destinationView:viewControllerToPresent.view duration:duration style:style completionAction:MPTransitionActionNone];
	
	[flipTransition setPresentingController:presentingController];
	
	[flipTransition perform:^(BOOL finished) {
		// under iPad for our fold transition, we need to be full screen modal (iPhone is always full screen modal)
		UIModalPresentationStyle oldStyle = [presentingController modalPresentationStyle];
		if (oldStyle != UIModalPresentationFullScreen && [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
			[presentingController setModalPresentationStyle:UIModalPresentationFullScreen];
		
		[presentingController presentViewController:viewControllerToPresent animated:NO completion:^{
			// restore previous modal presentation style
			if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
				[presentingController setModalPresentationStyle:oldStyle];
		}];
		
		if (completion)
			completion(YES);
	}];
}

+ (void)dismissViewControllerFromPresentingController:(UIViewController *)presentingController duration:(NSTimeInterval)duration style:(MPFlipStyle)style completion:(void (^)(BOOL finished))completion
{
	UIViewController *src = [presentingController presentedViewController];
	if (!src)
		[NSException raise:@"Invalid Operation" format:@"dismissViewControllerFromPresentingController:direction:completion: can only be performed on a view controller with a presentedViewController."];
	
    UIViewController *dest = (UIViewController *)presentingController;
	
	// find out the presentation context for the presenting view controller
	while (YES)// (![src definesPresentationContext])
	{
		if (![dest parentViewController])
			break;
		
		dest = [dest parentViewController];
	}
	
	MPFlipTransition *flipTransition = [[MPFlipTransition alloc] initWithSourceView:src.view destinationView:dest.view duration:duration style:style completionAction:MPTransitionActionNone];
	[flipTransition setDismissing:YES];
	[presentingController dismissViewControllerAnimated:NO completion:nil];
	[flipTransition perform:^(BOOL finished) {
		[dest.view setHidden:NO];
		if (completion)
			completion(YES);
	}];
}

@end

#pragma mark - UIViewController(MPFlipTransition)

@implementation UIViewController(MPFlipTransition)

- (void)presentViewController:(UIViewController *)viewControllerToPresent flipStyle:(MPFlipStyle)style completion:(void (^)(BOOL finished))completion
{
	[MPFlipTransition presentViewController:viewControllerToPresent from:self duration:[MPFlipTransition defaultDuration] style:style completion:completion];
}

- (void)dismissViewControllerWithFlipStyle:(MPFlipStyle)style completion:(void (^)(BOOL finished))completion
{
	[MPFlipTransition dismissViewControllerFromPresentingController:self duration:[MPFlipTransition defaultDuration] style:style completion:completion];
}

@end

#pragma mark - UINavigationController(MPFlipTransition)

@implementation UINavigationController(MPFlipTransition)

//- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
- (void)pushViewController:(UIViewController *)viewController flipStyle:(MPFlipStyle)style
{
	[MPFlipTransition transitionFromViewController:[self visibleViewController] 
								  toViewController:viewController 
										  duration:[MPFlipTransition defaultDuration]  
											 style:style 
										completion:^(BOOL finished) {
											[self pushViewController:viewController animated:NO];
										}
	 ];
}

- (UIViewController *)popViewControllerWithFlipStyle:(MPFlipStyle)style
{
	UIViewController *toController = [[self viewControllers] objectAtIndex:[[self viewControllers] count] - 2];
	
	[MPFlipTransition transitionFromViewController:[self visibleViewController] 
								  toViewController:toController 
										  duration:[MPFlipTransition defaultDuration] 
											 style:style
										completion:^(BOOL finished) {
											[self popViewControllerAnimated:NO];
										}
	 ];
	
	return toController;
}

@end
