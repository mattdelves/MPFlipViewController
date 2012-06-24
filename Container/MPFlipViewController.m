//
//  MPFlipViewController.m
//  MPFlipViewController
//
//  Created by Mark Pospesel on 6/4/12.
//  Copyright (c) 2012 Mark Pospesel. All rights reserved.
//

#import "MPFlipViewController.h"
#import	"MPFlipTransition.h"

#define MARGIN	44
#define SWIPE_THRESHOLD	125.0f
#define SWIPE_ESCAPE_VELOCITY 650.0f

@interface MPFlipViewController ()

@property (nonatomic, assign) MPFlipViewControllerOrientation orientation;
@property (nonatomic, strong) UIViewController *childViewController;
@property (nonatomic, strong) UIViewController *sourceController;
@property (nonatomic, strong) UIViewController *destinationController;
@property (nonatomic, assign) NSArray *gestureRecognizers;
@property (nonatomic, assign) BOOL gesturesAdded;
@property (nonatomic, readonly) BOOL isAnimating;
@property (nonatomic, assign, getter = isPanning) BOOL panning;
@property (nonatomic, strong) MPFlipTransition *flipTransition;
@property (assign, nonatomic) CGPoint panStart;
@property (nonatomic, assign) MPFlipViewControllerDirection direction;

@end

@implementation MPFlipViewController

@synthesize dataSource = _dataSource;

@synthesize orientation = _orientation;
@synthesize childViewController = _childViewController;
@synthesize gestureRecognizers = _gestureRecognizers;
@synthesize gesturesAdded = _gesturesAdded;
@synthesize panning = _panning;
@synthesize flipTransition = _flipTransition;
@synthesize panStart = _panStart;
@synthesize direction = _direction;
@synthesize sourceController = _sourceController;
@synthesize destinationController = _destinationController;

- (id)initWithOrientation:(MPFlipViewControllerOrientation)orientation
{
    self = [super init];
    if (self) {
        // Custom initialization
		_orientation = orientation;
		_direction = MPFlipViewControllerDirectionForward;
		_gesturesAdded = NO;
		_panning = NO;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.

	[self addGestures];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return ![self isAnimating];
}

#pragma mark - Properties

- (UIViewController *)viewController
{
	return [self childViewController];
}

- (BOOL)isAnimating
{
	return [self flipTransition] != nil;
}

- (BOOL)isFlipFrontPage
{
	return [[self flipTransition] stage] == MPFlipAnimationStage1;
}

#pragma mark - private instance methods

- (void)addGestures
{
	if ([self gesturesAdded])
		return;
	
	// Add our swipe gestures
	BOOL isHorizontal = ([self orientation] == MPFlipViewControllerOrientationHorizontal);
	UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeNext:)];
	left.direction = isHorizontal? UISwipeGestureRecognizerDirectionLeft : UISwipeGestureRecognizerDirectionUp;
	left.delegate = self;
	[self.view addGestureRecognizer:left];
	
	UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipePrev:)];
	right.direction = isHorizontal? UISwipeGestureRecognizerDirectionRight : UISwipeGestureRecognizerDirectionDown;
	right.delegate = self;
	[self.view addGestureRecognizer:right];
	
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
	tap.delegate = self;
	[self.view addGestureRecognizer:tap];
	
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
	pan.delegate = self;
	[self.view addGestureRecognizer:pan];
	
	self.gestureRecognizers = [NSArray arrayWithObjects:left, right, tap, pan, nil];

	[self setGesturesAdded:YES];
}

#pragma mark - public Instance methods

- (void)setViewController:(UIViewController *)viewController direction:(MPFlipViewControllerDirection)direction animated:(BOOL)animated completion:(void (^)(BOOL finished))completion
{
	UIViewController *previousController = [self viewController];
	
	BOOL isForward = (direction == MPFlipViewControllerDirectionForward);
	[[viewController view] setFrame:[self.view bounds]];
	[self addChildViewController:viewController]; // this calls [viewController willMoveToParentViewController:self] for us
	[self setChildViewController:viewController];
	[previousController willMoveToParentViewController:nil];
	
	if (animated && previousController)
	{
		[self startFlipToViewController:viewController 
					 fromViewController:previousController 
						  withDirection:(isForward? MPFlipStyleDefault : MPFlipStyleDirectionBackward)];
		
		[self.flipTransition perform:^(BOOL finished) {
			[self endFlip:YES completion:completion];
		}];
	}
	else 
	{
		[[self view] addSubview:[viewController view]];
		[[previousController view] removeFromSuperview];
		[viewController didMoveToParentViewController:self];
		if (completion)
			completion(YES);
		[previousController removeFromParentViewController]; // this calls [previousController didMoveToParentViewController:nil] for us
	}
}

#pragma mark - Gesture handlers

- (void)handleTap:(UITapGestureRecognizer *)gestureRecognizer
{
	if ([self isAnimating])
		return;
	
	CGPoint tapPoint = [gestureRecognizer locationInView:self.view];
	BOOL isHorizontal = [self orientation] == MPFlipViewControllerOrientationHorizontal;
	CGFloat value = isHorizontal? tapPoint.x : tapPoint.y;
	CGFloat dimension = isHorizontal? self.view.bounds.size.width : self.view.bounds.size.height;
	NSLog(@"Tap to flip");
	if (value <= MARGIN)
		[self gotoPreviousPage];
	else if (value >= dimension - MARGIN)
		[self gotoNextPage];
}

- (void)handleSwipePrev:(UIGestureRecognizer *)gestureRecognizer
{
	if ([self isAnimating])
		return;
	
	NSLog(@"Swipe to previous page");
	[self gotoPreviousPage];
}

- (void)handleSwipeNext:(UIGestureRecognizer *)gestureRecognizer
{
	if ([self isAnimating])
		return;
	
	NSLog(@"Swipe to next page");
	[self gotoNextPage];
}

- (void)handlePan:(UIPanGestureRecognizer *)gestureRecognizer
{
    UIGestureRecognizerState state = [gestureRecognizer state];
	CGPoint currentPosition = [gestureRecognizer locationInView:self.view];
	
	if (state == UIGestureRecognizerStateBegan)
	{
		if ([self isAnimating])
			return;
		
		// See if touch started near one of the edges, in which case we'll pan a page turn
		BOOL isHorizontal = [self orientation] == MPFlipViewControllerOrientationHorizontal;
		CGFloat value = isHorizontal? currentPosition.x : currentPosition.y;
		CGFloat dimension = isHorizontal? self.view.bounds.size.width : self.view.bounds.size.height;
		if (value <= MARGIN)
		{
			if (![self startFlipWithDirection:MPFlipViewControllerDirectionReverse])
				return;
		}
		else if (value >= dimension - MARGIN)
		{
			if (![self startFlipWithDirection:MPFlipViewControllerDirectionForward])
				return;
		}
		else
		{
			// Do nothing for now, but it might become a swipe later
			return;
		}
		
		[self setPanning:YES];
		[self setPanStart:currentPosition];
	}
	
	if ([self isPanning] && state == UIGestureRecognizerStateChanged)
	{
		CGFloat progress = [self progressFromPosition:currentPosition];
		if (progress < 1)
			[self.flipTransition setStage:MPFlipAnimationStage1 progress:progress];
		else
			[self.flipTransition setStage:MPFlipAnimationStage2 progress:progress - 1];
	}
	
	if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled)
	{
		if ([self isPanning])
        {
			// If moving slowly, let page fall either forward or back depending on where we were
			BOOL shouldFallBack = [self isFlipFrontPage];
			
			// finishAnimation
			CGFloat fromProgress = [self progressFromPosition:currentPosition];
			if (shouldFallBack != [self isFlipFrontPage])
			{
				// 2-stage animation (we're swiping either forward or back)
				if (([self isFlipFrontPage] && fromProgress > 1) || (![self isFlipFrontPage] && fromProgress < 1))
					fromProgress = 1;
				if (fromProgress > 1)
					fromProgress -= 1;
			}
			else
			{
				// 1-stage animation
				if (!shouldFallBack)
					fromProgress -= 1;
			}
			[[self flipTransition] animateFromProgress:fromProgress shouldFallBack:shouldFallBack completion:^(BOOL finished) {
				[self endFlip:!shouldFallBack completion:nil];
			}];
        }
	}
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
	// don't recognize any further gestures if we're in the middle of animating a page-turn
	if ([self isAnimating])
		return NO;
	
	return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	// Allow simultanoues pan & swipe recognizers
	return YES;
}

#pragma mark - Private instance methods

- (CGFloat)progressFromPosition:(CGPoint)position
{
	// Determine where we are in our page turn animation
	// 0 - 1 means flipping the front-side of the page
	// 1 - 2 means flipping the back-side of the page
	BOOL isForward = ([self direction] == MPFlipViewControllerDirectionForward);
	BOOL isVertical = ([self orientation] == MPFlipViewControllerOrientationVertical);
	
	CGFloat positionValue = isVertical? position.y : position.x;
	CGFloat startValue = isVertical? self.panStart.y : self.panStart.x;
	CGFloat dimensionValue = isVertical? self.view.frame.size.height : self.view.frame.size.width;
	CGFloat difference = positionValue - startValue;
	CGFloat halfWidth = fabsf(startValue - (dimensionValue / 2));
	CGFloat progress = difference / halfWidth * (isForward? - 1 : 1);
	
	//NSLog(@"Difference = %.2f, Half width = %.2f, rawProgress = %.4f", difference, halfWidth, progress);
	if (progress < 0)
		progress = 0;
	if (progress > 2)
		progress = 2;
	return progress;
}

- (BOOL)startFlipWithDirection:(MPFlipViewControllerDirection)direction
{
	if (![self dataSource])
		return NO;
	
	UIViewController *destinationController = (direction == MPFlipViewControllerDirectionForward)? 
	[[self dataSource] flipViewController:self viewControllerAfterViewController:[self viewController]] : 
	[[self dataSource] flipViewController:self viewControllerBeforeViewController:[self viewController]];
	
	if (!destinationController)
		return NO;
	
	[self startFlipToViewController:destinationController fromViewController:[self viewController] withDirection:direction];
	
	return YES;
}

- (void)startFlipToViewController:(UIViewController *)destinationController fromViewController:(UIViewController *)sourceController withDirection:(MPFlipViewControllerDirection)direction
{
	BOOL isForward = (direction == MPFlipViewControllerDirectionForward);
	BOOL isVertical = ([self orientation] == MPFlipViewControllerOrientationVertical);
	[self setSourceController:sourceController];
	[self setDestinationController:destinationController];
	[self setDirection:direction];
	self.flipTransition = [[MPFlipTransition alloc] initWithSourceView:[sourceController view] 
													   destinationView:[destinationController view] 
															  duration:1.5 
																 style:((isForward? MPFlipStyleDefault : MPFlipStyleDirectionBackward) | (isVertical? MPFlipStyleOrientationVertical : MPFlipStyleDefault))
													  completionAction:MPTransitionActionAddRemove];
	
	[self.flipTransition buildLayers];
	
	// set the back page in the vertical position (midpoint of animation)
	[self.flipTransition prepareForStage2];
}

- (void)endFlip:(BOOL)transitionCompleted completion:(void (^)(BOOL finished))completion
{
	BOOL didStartAsPan = [self isPanning];
	// clear some flags
	[self setFlipTransition:nil];
	[self setPanning:NO];
	
	if (transitionCompleted)
	{
		// If page turn was completed, then we need to send our various notifications as per the Containment API
		if (didStartAsPan)
		{
			// these weren't sent at beginning (because we couldn't know beforehand 
			// whether the gesture would result in a page turn or not)
			[self addChildViewController:self.destinationController]; // this calls [self.destinationController willMoveToParentViewController:self] for us
			[self setChildViewController:self.destinationController];
			[self.sourceController willMoveToParentViewController:nil];
		}
		
		// final set of containment notifications
		[self.destinationController didMoveToParentViewController:self];
		[self.sourceController removeFromParentViewController]; // this calls [self.sourceController didMoveToParentViewController:nil] for us
	}
	
	if (completion)
		completion(YES);
	
	// clear remaining flags
	self.sourceController = nil;
	self.destinationController = nil;
}

- (void)gotoPreviousPage
{
	if (![self dataSource])
		return;
	
	UIViewController *previousController = [[self dataSource] flipViewController:self viewControllerBeforeViewController:[self viewController]];
	if (!previousController)
		return;
	
	[self setViewController:previousController direction:MPFlipViewControllerDirectionReverse animated:YES completion:nil];
}

- (void)gotoNextPage
{
	if (![self dataSource])
		return;
	
	UIViewController *nextController = [[self dataSource] flipViewController:self viewControllerAfterViewController:[self viewController]];
	if (!nextController)
		return;
	
	[self setViewController:nextController direction:MPFlipViewControllerDirectionForward animated:YES completion:nil];	
}

@end
