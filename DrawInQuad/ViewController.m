#import "ViewController.h"

#if defined(__ARM_NEON__)
	#include <arm_neon.h>
#endif
#import <GLKit/GLKMath.h>

#import "UIView+draggable.h"
#import "BlocksKit.h"



static NSString *kLastSrcImageNameKey = @"ViewController_LastSrcImageName";


#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunneeded-internal-declaration"

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

	static inline int modulo(int dividendA, int divisorN)
	{
		if (divisorN < 0) // you can check for divisorN == 0 separately and do what you want
			return modulo(-dividendA, -divisorN);
		
		int ret = dividendA % divisorN;
		if (ret < 0)
			ret += divisorN;
		
		return ret;
	}

	#if !defined(CLAMP)
		#define CLAMP(V,L,H)	(MIN(H, MAX(L, V)))
	#endif
	#if !defined(WITHIN)
		#define WITHIN(V,L,H)	((V)>(L) && (V)<(H))
	#endif
	
	static inline float ratioAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 *out_nearestPoint)
	{
		GLKVector2 segmentDelta = GLKVector2Subtract(segmentBPoint, segmentAPoint);
		GLKVector2 freeToADelta = GLKVector2Subtract(freePoint, segmentAPoint);
		
		float ratioAlongSegment = GLKVector2DotProduct(freeToADelta, segmentDelta) / GLKVector2LengthSqr(segmentDelta);
		
		if (out_nearestPoint != NULL) {
			if (ratioAlongSegment <= 0.0f)
				*out_nearestPoint = segmentAPoint;
			else if (ratioAlongSegment >= 1.0f)
				*out_nearestPoint = segmentBPoint;
			else
				*out_nearestPoint = GLKVector2Add(segmentAPoint, GLKVector2MultiplyScalar(segmentDelta, ratioAlongSegment));
		}
		
		return ratioAlongSegment;
	}

#pragma clang diagnostic pop



@interface ViewController () {
	NSArray *_srcPossibilityNames;
	
	QBPopupMenu *_popupMenu;
	
	UIImage *_srcImage;
	CFDataRef _srcData;
	int _srcWidth, _srcHeight;
	
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
	return [_outlineView pointAtIndexedSubscript:0];
}
- (CGPoint)point2 {
	return [_outlineView pointAtIndexedSubscript:1];
}
- (CGPoint)point3 {
	return [_outlineView pointAtIndexedSubscript:2];
}
- (CGPoint)point4 {
	return [_outlineView pointAtIndexedSubscript:3];
}

- (void)setPoint1:(CGPoint)point {
	[_outlineView setPoint:point atIndexedSubscript:0];
}
- (void)setPoint2:(CGPoint)point {
	[_outlineView setPoint:point atIndexedSubscript:1];
}
- (void)setPoint3:(CGPoint)point {
	[_outlineView setPoint:point atIndexedSubscript:2];
}
- (void)setPoint4:(CGPoint)point {
	[_outlineView setPoint:point atIndexedSubscript:3];
}

/// Based on a loose understanding of Wikipedia's article on Bilinear interpolation (https://en.wikipedia.org/wiki/Bilinear_interpolation).
/// 	Probably not the best algoritm for this— works, but with more distortion as the points become less square.
/// 	Seems to show better results when the left and right sides of the points quad are parallel.
GLKVector2 surfaceSTToTexelUV(GLKVector2 surfaceST, GLKVector2 pointSTs[4], GLKVector2 pointUVs[4])
{
	GLKVector2 nearestPointOn03Segment, nearestPointOn12Segment;
	float ratioAlong03 = ratioAlongSegment(surfaceST, pointSTs[0], pointSTs[3], &nearestPointOn03Segment);
	float ratioAlong12 = ratioAlongSegment(surfaceST, pointSTs[1], pointSTs[2], &nearestPointOn12Segment);
	
	float ratioBetweenNearest03And12 = ratioAlongSegment(surfaceST, nearestPointOn03Segment, nearestPointOn12Segment, NULL);
	float ratiosAlong03And12Rebalanced = ratioAlong03 + (ratioAlong12 - ratioAlong03) * ratioBetweenNearest03And12;
	
	GLKVector2 texelUV = GLKVector2Make(ratioBetweenNearest03And12, ratiosAlong03And12Rebalanced);
	return texelUV;
}

static inline GLKVector2 GLKVector2FromCGPoint(CGPoint point) {
	return GLKVector2Make(point.x, point.y);
}

#define GEN_DEST_IMAGE_WRAP_ST 0

size_t genDestImagePixelBytesAtPosition(void *info, void *buffer, off_t position, size_t requestedByteCount)
{
	const int kBytesPerPixel = 4;
	
	ViewController *self = (__bridge ViewController *)info;
	UInt8 *byteBuffer = (UInt8 *)buffer;
	
	const unsigned int width = self->_destImageWidth,
		height = self->_destImageHeight,
		pixelCount = width * height;
	
	const unsigned int pixelIndex = (unsigned int)(position / kBytesPerPixel);
	if (pixelIndex >= pixelCount)
		return 0;
	const unsigned int pixelX = pixelIndex % width,
		pixelY = pixelIndex / width;
	
	const CGPoint points[4] = { self.point1, self.point2, self.point3, self.point4 };
	
	const GLKVector2 texelUV = surfaceSTToTexelUV(
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
	
	int nearestTexelXY[2] = {
		roundf(texelUV.s * self->_srcWidth - 0.5f),
		roundf(texelUV.t * self->_srcHeight - 0.5f)
	};
	#if GEN_DEST_IMAGE_WRAP_ST
		if (!WITHIN(nearestTexelXY[0], 0, self->_srcWidth - 1))
			nearestTexelXY[0] = modulo(nearestTexelXY[0], self->_srcWidth);
		if (!WITHIN(nearestTexelXY[1], 0, self->_srcHeight - 1))
			nearestTexelXY[1] = modulo(nearestTexelXY[1], self->_srcHeight);
	#else
		if (!WITHIN(nearestTexelXY[0], 0, self->_srcWidth - 1))
			nearestTexelXY[0] = CLAMP(nearestTexelXY[0], 0, self->_srcWidth - 1);
		if (!WITHIN(nearestTexelXY[1], 0, self->_srcHeight - 1))
			nearestTexelXY[1] = CLAMP(nearestTexelXY[1], 0, self->_srcHeight - 1);
	#endif
	
	const int texelIndex = nearestTexelXY[1] * self->_srcWidth + nearestTexelXY[0];
	
	UInt8 nearestTexelSample[4];
	CFDataGetBytes(
		self->_srcData,
		CFRangeMake(texelIndex * kBytesPerPixel, kBytesPerPixel),
		nearestTexelSample
	);
	
	const unsigned int pixelByteOffset = position % kBytesPerPixel;
	const size_t byteCount = kBytesPerPixel - pixelByteOffset;
	
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
		CGFloat destScale = 1;//UIScreen.mainScreen.scale;
		unsigned int width = _destImageWidth = destBoundsSize.width * destScale,
			height = _destImageHeight = destBoundsSize.height * destScale;
		
		CGImageRef srcCGImage = _srcImage.CGImage;
		if (!_srcData) {
			_srcData = CGDataProviderCopyData(CGImageGetDataProvider(srcCGImage));
			_srcWidth = (int)CGImageGetWidth(srcCGImage);
			_srcHeight = (int)CGImageGetHeight(srcCGImage);
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
	popupMenu.color = [UIColor.whiteColor colorWithAlphaComponent:0.9];
	popupMenu.highlightedColor = self.view.tintColor;
	popupMenu.textColor = UIColor.blackColor;
	popupMenu.arrowDirection = QBPopupMenuArrowDirectionLeft;
	popupMenu.delegate = self;
    _popupMenu = popupMenu;
	
	[_imageSelectionButton setTitle:nil forState:UIControlStateHighlighted];
	[_imageSelectionButton setTitle:nil forState:UIControlStateDisabled];
	[_imageSelectionButton setTitle:nil forState:UIControlStateSelected];
	
	NSString *srcImageName = [NSUserDefaults.standardUserDefaults stringForKey:kLastSrcImageNameKey];
	if (srcImageName == nil || ![_srcPossibilityNames containsObject:srcImageName])
		srcImageName = _srcPossibilityNames.firstObject;
	
	[self switchToImageNamed:srcImageName];
	
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
	
	[self redrawDestImage];
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
	UIButton *imageSelectionButton = self.imageSelectionButton;
	[UIView animateWithDuration:0.5
		animations:^{
			imageSelectionButton.selected = YES;
		}
		completion:^(BOOL finished) {
			imageSelectionButton.selected = YES;
		}
	];
	
	UIView *viewSender = (UIView *)sender;
	[_popupMenu showInView:self.view targetRect:viewSender.frame animated:YES];
}

- (void)popupMenuWillDisappear:(QBPopupMenu *)popupMenu
{
	if (popupMenu != _popupMenu)
		return;
	
	UIButton *imageSelectionButton = self.imageSelectionButton;
	[UIView animateWithDuration:0.5
		animations:^{
			imageSelectionButton.selected = NO;
		}
	];
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
	
	[_imageSelectionButton setTitle:imageName forState:UIControlStateNormal];
	[_imageSelectionButton sizeToFit];
	
	_srcImage = [UIImage imageNamed:[imageName stringByAppendingPathExtension:@"png"]];
	if (_srcData) {
		CFRelease(_srcData);
		_srcData = NULL;
	}
	
	_destImage = nil;
	
	[NSUserDefaults.standardUserDefaults setObject:imageName forKey:kLastSrcImageNameKey];
}

- (IBAction)redrawNow:(id)sender
{
	[self redrawDestImage];
}

- (void)redrawDestImage
{
	_destImage = nil;
	_imageView.image = self.destImage;
}

@end
