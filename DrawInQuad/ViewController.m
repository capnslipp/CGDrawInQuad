#import "ViewController.h"
#import "UIView+draggable.h"



@interface ViewController () {
	UIImage *_srcImage;
	UIImage *_destImage;
}

- (CGPoint)handleCenterFromPoint:(CGPoint)point;
- (CGPoint)pointFromHandleCenter:(CGPoint)handlePosition;

- (void)pointsDidChange;

@end


@implementation ViewController

@synthesize imageView=_imageView;

- (CGPoint)point1 {
	return ((NSValue *)self.outlineView[0]).CGPointValue;
}
- (CGPoint)point2 {
	return ((NSValue *)self.outlineView[1]).CGPointValue;
}
- (CGPoint)point3 {
	return ((NSValue *)self.outlineView[2]).CGPointValue;
}
- (CGPoint)point4 {
	return ((NSValue *)self.outlineView[3]).CGPointValue;
}

- (void)setPoint1:(CGPoint)point {
	self.outlineView[0] = [NSValue valueWithCGPoint:point];
}
- (void)setPoint2:(CGPoint)point {
	self.outlineView[1] = [NSValue valueWithCGPoint:point];
}
- (void)setPoint3:(CGPoint)point {
	self.outlineView[2] = [NSValue valueWithCGPoint:point];
}
- (void)setPoint4:(CGPoint)point {
	self.outlineView[3] = [NSValue valueWithCGPoint:point];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
	
	self.point1 = CGPointMake(0.0, 0.0);
	self.point2 = CGPointMake(0.1, 0.9);
	self.point3 = CGPointMake(1.0, 1.0);
	self.point4 = CGPointMake(0.9, 0.1);
	[self pointsDidChange];
	
	[self.handle1 enableDragging];
	[self.handle2 enableDragging];
	[self.handle3 enableDragging];
	[self.handle4 enableDragging];
	
	_srcImage = [UIImage imageNamed:@"test"];
	
	_destImage = _srcImage;
	_imageView.image = _destImage;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[UIView animateWithDuration:duration animations:^{
		[self pointsDidChange];
	}];
}


- (CGPoint)handleCenterFromPoint:(CGPoint)point
{
	CGRect bounds = self.imageView.frame;
	return CGPointMake(
		bounds.size.width * point.x + bounds.origin.x,
		bounds.size.height * point.y + bounds.origin.y
	);
}

- (CGPoint)pointFromHandleCenter:(CGPoint)handleCenter
{
	CGRect bounds = self.imageView.frame;
	return CGPointMake(
		(handleCenter.x - bounds.origin.x) / bounds.size.width,
		(handleCenter.y - bounds.origin.y) / bounds.size.height
	);
}

- (void)pointsDidChange
{
	self.handle1.center = [self handleCenterFromPoint:self.point1];
	self.handle2.center = [self handleCenterFromPoint:self.point2];
	self.handle3.center = [self handleCenterFromPoint:self.point3];
	self.handle4.center = [self handleCenterFromPoint:self.point4];
}

- (IBAction)draggedHandle:(id)sender
{
	if (sender == self.handle1)
		self.point1 = [self pointFromHandleCenter:self.handle1.center];
	else if (sender == self.handle2)
		self.point2 = [self pointFromHandleCenter:self.handle2.center];
	else if (sender == self.handle3)
		self.point3 = [self pointFromHandleCenter:self.handle3.center];
	else if (sender == self.handle4)
		self.point4 = [self pointFromHandleCenter:self.handle4.center];
}

@end
