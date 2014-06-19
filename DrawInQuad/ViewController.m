#import "ViewController.h"
#import "UIView+draggable.h"



@interface ViewController () {
	UIImage *_srcImage;
	UIImage *_destImage;
	
	size_t _destImageTotalBytes;
	unsigned int _destImageWidth;
	unsigned int _destImageHeight;
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

size_t genDestImageBytesAtPosition(void *info, void *buffer, off_t position, size_t requestedByteCount)
{
	ViewController *self = (__bridge ViewController *)info;
	unsigned int width = self->_destImageWidth,
		height = self->_destImageHeight,
		pixelCount = width * height;
	
	char *byteBuffer = (char *)buffer;
	
	unsigned int pixelIndex = (unsigned int)(position / 4);
	if (pixelIndex >= pixelCount)
		return 0;
	unsigned int pixelX = pixelIndex % width,
		pixelY = pixelIndex / width;
	CGFloat pixelU = (CGFloat)pixelX / width,
		pixelV = (CGFloat)pixelY / height;
	
	unsigned int pixelByteOffset = position % 4;
	size_t byteCount = 4 - pixelByteOffset;
	
	switch (pixelByteOffset)
	{
		case 0:
			byteBuffer[0] = 0;
		case 1:
			byteBuffer[1] = 0;
		case 2:
			byteBuffer[2] = 0;
		case 3:
			byteBuffer[3] = 0;
			break;
		
		default:
			assert(pixelByteOffset < 4);
	}
	
	return byteCount;
}

- (UIImage *)destImage
{
	if (!_destImage) {
		CGSize srcImageSize = _srcImage.size;
		_destImageWidth = srcImageSize.width;
		_destImageHeight = srcImageSize.height;
		
		CGImageRef srcCGImage = _srcImage.CGImage;
		
		size_t bitsPerComponent = CGImageGetBitsPerComponent(srcCGImage);
		size_t bitsPerPixel = bitsPerComponent * 4;
		size_t bitsPerRow = bitsPerPixel * _destImageWidth,
			bytesPerRow = bitsPerRow >> 3;
		_destImageTotalBytes = bytesPerRow * _destImageHeight;
		
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
		CGDataProviderRef dataProvider = CGDataProviderCreateDirect(
			(__bridge void *)self,
			_destImageTotalBytes,
			&((CGDataProviderDirectCallbacks){
				.version = 0,
				.getBytePointer = NULL,
				.releaseBytePointer = NULL,
				.getBytesAtPosition = genDestImageBytesAtPosition,
				.releaseInfo = NULL
			})
		);
		
		CGImageRef destCGImage = CGImageCreate(
			_destImageWidth, _destImageHeight,
			bitsPerComponent, bitsPerPixel, bytesPerRow,
			colorSpace,
			kCGBitmapByteOrderDefault | kCGImageAlphaLast,
			dataProvider,
			NULL,
			FALSE /* shouldInterpolate */,
			kCGRenderingIntentDefault
		);
		_destImage = [[UIImage alloc] initWithCGImage:destCGImage];
		CGImageRelease(destCGImage);
		
		CGDataProviderRelease(dataProvider);
		CGColorSpaceRelease(colorSpace);
	}
	return _destImage;
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
	
	_imageView.image = self.destImage;
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
	
	_destImage = nil;
	_imageView.image = self.destImage; // force refresh, for now
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
