#import "ViewController.h"

#if defined(__ARM_NEON__)
	#include <arm_neon.h>
#endif
#import <GLKit/GLKMath.h>

#import "UIView+draggable.h"
#import "BlocksKit.h"
#import "QBPopupMenu.h"


/// Just GLKVector2Length() with the sqrt() operation removed.
static inline float GLKVector2LengthSqr(GLKVector2 vector)
{
	#if defined(__ARM_NEON__)
		float32x2_t v = vmul_f32(
			*(float32x2_t *)&vector,
			*(float32x2_t *)&vector
		);
		v = vpadd_f32(v, v);
		return vget_lane_f32(v, 0);
	#else
		return vector.v[0] * vector.v[0] + vector.v[1] * vector.v[1];
	#endif
}

/// Just GLKVector2Distance() with the sqrt() operation removed.
static inline float GLKVector2DistanceSqr(GLKVector2 vectorStart, GLKVector2 vectorEnd)
{
	return GLKVector2LengthSqr(GLKVector2Subtract(vectorEnd, vectorStart));
}



@interface ViewController () {
	NSArray *_srcPossibilityNames;
	
	QBPopupMenu *_popupMenu;
	
	UIImage *_srcImage;
	CFDataRef _srcData;
	size_t _srcWidth, _srcHeight;
	
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

GLKVector2 surfaceSTToTexelUV(GLKVector2 surfaceST, GLKVector2 pointSTs[4], GLKVector2 pointUVs[4])
{
	CGFloat distSqrToEachPoint[4] = {
		GLKVector2DistanceSqr(surfaceST, pointSTs[0]),
		GLKVector2DistanceSqr(surfaceST, pointSTs[1]),
		GLKVector2DistanceSqr(surfaceST, pointSTs[2]),
		GLKVector2DistanceSqr(surfaceST, pointSTs[3]),
	};
	CGFloat distSqrSum = distSqrToEachPoint[0] + distSqrToEachPoint[1] + distSqrToEachPoint[2] + distSqrToEachPoint[3];
	
	CGFloat distSqrSumReciprocal = 1.0f / distSqrSum;
	CGFloat weights[4] = {
		(distSqrSum - distSqrToEachPoint[0]) * distSqrSumReciprocal,
		(distSqrSum - distSqrToEachPoint[1]) * distSqrSumReciprocal,
		(distSqrSum - distSqrToEachPoint[2]) * distSqrSumReciprocal,
		(distSqrSum - distSqrToEachPoint[3]) * distSqrSumReciprocal,
	};
	
	GLKVector2 weightedUVs[4] = {
		GLKVector2MultiplyScalar(pointUVs[0], weights[0]),
		GLKVector2MultiplyScalar(pointUVs[1], weights[1]),
		GLKVector2MultiplyScalar(pointUVs[2], weights[2]),
		GLKVector2MultiplyScalar(pointUVs[3], weights[3]),
	};
	GLKVector2 texelUV = GLKVector2Add(weightedUVs[0],
		GLKVector2Add(weightedUVs[1],
			GLKVector2Add(weightedUVs[2], weightedUVs[3])
		)
	);
	return texelUV;
}

static inline GLKVector2 GLKVector2FromCGPoint(CGPoint point) {
	return GLKVector2Make(point.x, point.y);
}

size_t genDestImagePixelBytesAtPosition(void *info, void *buffer, off_t position, size_t requestedByteCount)
{
	ViewController *self = (__bridge ViewController *)info;
	UInt8 *byteBuffer = (UInt8 *)buffer;
	
	unsigned int width = self->_destImageWidth,
		height = self->_destImageHeight,
		pixelCount = width * height;
	
	unsigned int pixelIndex = (unsigned int)(position / 4);
	if (pixelIndex >= pixelCount)
		return 0;
	unsigned int pixelX = pixelIndex % width,
		pixelY = pixelIndex / width;
	
	CGPoint points[4] = { self.point1, self.point2, self.point3, self.point4 };
	
	GLKVector2 texelUV = surfaceSTToTexelUV(
		GLKVector2Make((CGFloat)pixelX / width, (CGFloat)pixelY / height),
		(GLKVector2[4]){
			GLKVector2FromCGPoint(points[0]),
			GLKVector2FromCGPoint(points[1]),
			GLKVector2FromCGPoint(points[2]),
			GLKVector2FromCGPoint(points[3])
		},
		(GLKVector2[4]){
			GLKVector2Make(0.0f, 0.0f),
			GLKVector2Make(0.0f, 1.0f),
			GLKVector2Make(1.0f, 1.0f),
			GLKVector2Make(1.0f, 0.0f)
		}
	);
	
	unsigned int pixelByteOffset = position % 4;
	size_t byteCount = 4 - pixelByteOffset;
	
	size_t nearestTexelXY[2] = {
		roundf(texelUV.s * self->_srcWidth),
		roundf(texelUV.t * self->_srcHeight),
	};
	UInt8 nearestTexelSample[4];
	CFDataGetBytes(
		self->_srcData,
		CFRangeMake(nearestTexelXY[1] * self->_srcWidth + nearestTexelXY[0], 4),
		nearestTexelSample
	);
	
	switch (pixelByteOffset)
	{
		case 0:
			byteBuffer[0] = nearestTexelSample[0];
		case 1:
			byteBuffer[1] = nearestTexelSample[1];
		case 2:
			byteBuffer[2] = nearestTexelSample[2];
		case 3:
			byteBuffer[3] = nearestTexelSample[3];
			break;
		
		default:
			assert(pixelByteOffset < 4);
	}
	
	return byteCount;
}

size_t genDestImageBytesAtPosition(void *info, void *buffer, off_t position, size_t count)
{
	ViewController *self = (__bridge ViewController *)info;
	UInt8 *byteBuffer = (UInt8 *)buffer;
	
	unsigned int width = self->_destImageWidth,
		height = self->_destImageHeight,
		pixelCount = width * height;
	
	size_t byteCount = pixelCount * 4;
	if (count < byteCount)
		byteCount = count;
	
	size_t remainingByteCount = byteCount;
	while (remainingByteCount > 0) {
		size_t bytesGenerated = genDestImagePixelBytesAtPosition(info, &byteBuffer[position], position, remainingByteCount);
		
		position += bytesGenerated;
		remainingByteCount -= bytesGenerated;
	}
	
	return byteCount;
}

- (UIImage *)destImage
{
	if (!_destImage) {
		CGSize destBoundsSize = self.imageView.bounds.size;
		CGFloat destScale = UIScreen.mainScreen.scale;
		unsigned int width = _destImageWidth = destBoundsSize.width * destScale,
			height = _destImageHeight = destBoundsSize.height * destScale;
		
		CGImageRef srcCGImage = _srcImage.CGImage;
		if (!_srcData) {
			_srcData = CGDataProviderCopyData(CGImageGetDataProvider(srcCGImage));
			_srcWidth = CGImageGetWidth(srcCGImage);
			_srcHeight = CGImageGetHeight(srcCGImage);
		}
		
		size_t bitsPerComponent = CGImageGetBitsPerComponent(srcCGImage);
		size_t bitsPerPixel = bitsPerComponent * 4;
		size_t bitsPerRow = bitsPerPixel * width,
			bytesPerRow = bitsPerRow >> 3;
		_destImageTotalBytes = bytesPerRow * height;
		
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
			width, height,
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

- (void)generateSrcPossibilities
{
	NSMutableArray *srcPossibilityNames = [[NSMutableArray alloc] initWithArray:[NSBundle.mainBundle pathsForResourcesOfType:@"png" inDirectory:@""]];
	[srcPossibilityNames bk_performMap:^(NSString *path) {
		NSString *fileName = path.pathComponents.lastObject;
		
		NSUInteger extensionWithDotLength = path.pathExtension.length; // doesn't yet include the dots
		if (extensionWithDotLength > 0)
			++extensionWithDotLength;
		
		NSString *name = [fileName substringToIndex:(fileName.length - extensionWithDotLength)];
		return name;
	}];
	[srcPossibilityNames bk_performSelect:^(NSString *name) {
		return [name hasPrefix:@"src."];
	}];
	_srcPossibilityNames = srcPossibilityNames;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	[self generateSrcPossibilities];
	
	NSArray *popupMenuItems = [_srcPossibilityNames bk_map:^(NSString *name) {
		return [QBPopupMenuItem itemWithTitle:name target:self action:@selector(switchToImage:)];
	}];
    QBPopupMenu *popupMenu = [[QBPopupMenu alloc] initWithItems:popupMenuItems];
    //popupMenu.highlightedColor = [[UIColor colorWithRed:0 green:0.478 blue:1.0 alpha:1.0] colorWithAlphaComponent:0.8];
	//popupMenu.arrowDirection = QBPopupMenuArrowDirectionDown;
    _popupMenu = popupMenu;
	
	[self switchToImageNamed:_srcPossibilityNames.firstObject];
	
	self.point1 = CGPointMake(0.0, 0.0);
	self.point2 = CGPointMake(0.1, 0.9);
	self.point3 = CGPointMake(1.0, 1.0);
	self.point4 = CGPointMake(0.9, 0.1);
	
	[self.handle1 enableDragging];
	[self.handle2 enableDragging];
	[self.handle3 enableDragging];
	[self.handle4 enableDragging];
}

- (void)dealloc
{
	if (_srcData) {
		CFRelease(_srcData);
		_srcData = NULL;
	}
}

- (void)viewDidLayoutSubviews
{
	[self pointsDidChange];
	[self.outlineView setNeedsLayout];
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

- (CGRect)handleBounds {
	return self.imageView.frame;
}

- (CGPoint)handleCenterFromPoint:(CGPoint)point
{
	CGRect bounds = self.handleBounds;
	return CGPointMake(
		bounds.size.width * point.x + bounds.origin.x,
		bounds.size.height * point.y + bounds.origin.y
	);
}

- (CGPoint)pointFromHandleCenter:(CGPoint)handleCenter
{
	CGRect bounds = self.handleBounds;
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
	UIButton *buttonSender = (UIButton *)sender;
	CGRect allowedRegion = self.imageView.frame;
	CGPoint senderCenter = buttonSender.center;
	if (!CGRectContainsPoint(allowedRegion, senderCenter)) {
		CGPoint closestInRegionPoint = senderCenter;
		
		CGPoint minAllowed = CGPointMake(CGRectGetMinX(allowedRegion), CGRectGetMinY(allowedRegion)),
			maxAllowed = CGPointMake(CGRectGetMaxX(allowedRegion), CGRectGetMaxY(allowedRegion));
		
		if (closestInRegionPoint.x < minAllowed.x)
			closestInRegionPoint.x = minAllowed.x;
		else if (closestInRegionPoint.x > maxAllowed.x)
			closestInRegionPoint.x = maxAllowed.x;
		
		if (closestInRegionPoint.y < minAllowed.y)
			closestInRegionPoint.y = minAllowed.y;
		else if (closestInRegionPoint.y > maxAllowed.y)
			closestInRegionPoint.y = maxAllowed.y;
		
		buttonSender.center = senderCenter = closestInRegionPoint;
	}
	
	if (sender == self.handle1)
		self.point1 = [self pointFromHandleCenter:self.handle1.center];
	else if (sender == self.handle2)
		self.point2 = [self pointFromHandleCenter:self.handle2.center];
	else if (sender == self.handle3)
		self.point3 = [self pointFromHandleCenter:self.handle3.center];
	else if (sender == self.handle4)
		self.point4 = [self pointFromHandleCenter:self.handle4.center];
}

- (IBAction)selectImage:(id)sender
{
	UIButton *buttonSender = (UIButton *)sender;
	
	[_popupMenu showInView:self.view targetRect:buttonSender.frame animated:YES];
}

- (void)switchToImage:(QBPopupMenuItem *)sender
{
	NSString *imageName = sender.title;
	[self switchToImageNamed:imageName];
}
- (void)switchToImageNamed:(NSString *)imageName
{
	if (![_srcPossibilityNames containsObject:imageName])
		return;
	
	_imageSelectionButton.titleLabel.text = imageName;
	[_imageSelectionButton sizeToFit];
	
	_srcImage = [UIImage imageNamed:[imageName stringByAppendingPathExtension:@"png"]];
	if (_srcData) {
		CFRelease(_srcData);
		_srcData = NULL;
	}
	_srcWidth = _srcHeight = 0;
	
	_destImage = nil;
}

@end
