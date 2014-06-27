#import "ViewController.h"

#if defined(__ARM_NEON__)
	#include <arm_neon.h>
#endif
#import <GLKit/GLKMath.h>

#import "UIView+draggable.h"
#import "BlocksKit.h"



static NSString *kLastSrcImageNameKey = @"ViewController_LastSrcImageName";
static NSString *kLastWrapUVsNameKey = @"ViewController_WrapUVsName";


#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

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

	static inline float GLKVector2CrossProduct(GLKVector2 vectorLeft, GLKVector2 vectorRight)
	{
		return GLKVector2DotProduct(
			GLKVector2Make(vectorLeft.x, -vectorLeft.y),
			GLKVector2Make(vectorRight.y, vectorRight.x)
		);
	}

	/// Returns a vector perpendicular to the given vector, rotate 90° counter-clockwise.
	/// Devised by F. S. Hill Jr. in Graphics Gems IV (1994).
	///		@source: http://mathworld.wolfram.com/PerpendicularVector.html
	static inline GLKVector2 GLKVector2Perp(GLKVector2 vector)
	{
		return GLKVector2Make(-vector.y, vector.x);
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

	/// @source: Real-Time Collision Detection by Christer Ericson (Morgan Kaufmann, 2005) - Chapter 3: A Math and Geometry Primer - Section 3.4 Barycentric Coordinates
	static inline GLKVector3 barycentricCoords2(GLKVector2 point, GLKVector2 tri[3])
	{
		GLKVector2 v0 = GLKVector2Subtract(tri[1], tri[0]),
			v1 = GLKVector2Subtract(tri[2], tri[0]),
			v2 = GLKVector2Subtract(point, tri[0]);
		
		float d00 = GLKVector2DotProduct(v0, v0),
			d01 = GLKVector2DotProduct(v0, v1),
			d11 = GLKVector2DotProduct(v1, v1),
			d20 = GLKVector2DotProduct(v2, v0),
			d21 = GLKVector2DotProduct(v2, v1);
		
		float denomReciprocal = 1.0f / (d00 * d11 - d01 * d01);
		float v = (d11 * d20 - d01 * d21) * denomReciprocal;
		float w = (d00 * d21 - d01 * d20) * denomReciprocal;
		
		return GLKVector3Make(1.0f - v - w, v, w);
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
	
	BOOL _wrapUVs;
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
GLKVector2 surfaceSTToTexelUV_bilinearQuad(GLKVector2 surfaceST, GLKVector2 pointSTs[4], GLKVector2 pointUVs[4])
{
	GLKVector2 nearestPointOn03Segment, nearestPointOn12Segment;
	float ratioAlong03 = ratioAlongSegment(surfaceST, pointSTs[0], pointSTs[3], &nearestPointOn03Segment);
	float ratioAlong12 = ratioAlongSegment(surfaceST, pointSTs[1], pointSTs[2], &nearestPointOn12Segment);
	
	GLKVector2 nearestPointOn03SegmentUV = GLKVector2Lerp(pointUVs[0], pointUVs[3], ratioAlong03);
	GLKVector2 nearestPointOn12SegmentUV = GLKVector2Lerp(pointUVs[1], pointUVs[2], ratioAlong12);
	
	float ratioBetweenNearest03And12 = ratioAlongSegment(surfaceST, nearestPointOn03Segment, nearestPointOn12Segment, NULL);
	
	GLKVector2 texelUV = GLKVector2Lerp(nearestPointOn03SegmentUV, nearestPointOn12SegmentUV, ratioBetweenNearest03And12);
	return texelUV;
}

GLKVector2 surfaceSTToTexelUV_barycentricTri(GLKVector2 surfaceST, GLKVector2 pointSTs[3], GLKVector2 pointUVs[3])
{
	GLKVector3 barycentricCoords = barycentricCoords2(surfaceST, pointSTs);
	
	GLKVector2 pointUVsPortioned[3] = {
		GLKVector2MultiplyScalar(pointUVs[0], barycentricCoords.v[0]),
		GLKVector2MultiplyScalar(pointUVs[1], barycentricCoords.v[1]),
		GLKVector2MultiplyScalar(pointUVs[2], barycentricCoords.v[2])
	};
	
	GLKVector2 texelUV = GLKVector2Add(GLKVector2Add(pointUVsPortioned[0], pointUVsPortioned[1]), pointUVsPortioned[2]);
	return texelUV;
}

GLKVector2 surfaceSTToTexelUV_barycentricQuad(GLKVector2 surfaceST, GLKVector2 pointSTs[4], GLKVector2 pointUVs[4])
{
	static const int kStarboardTriInQuadIndices[3] = { 0, 1, 2 };
	static const int kPortTriInQuadIndices[3] = { 0, 2, 3 };
	
	//// @source http://stackoverflow.com/questions/1560492/how-to-tell-whether-a-point-is-to-the-right-or-left-side-of-a-line
	float lineVsPointCross = GLKVector2CrossProduct(
		GLKVector2Subtract(pointSTs[2], pointSTs[0]),
		GLKVector2Subtract(surfaceST, pointSTs[0])
	);
	BOOL starboardSide = lineVsPointCross > 0.0f;
	
	const int *triInQuadIndices = starboardSide ? kStarboardTriInQuadIndices : kPortTriInQuadIndices;
	return surfaceSTToTexelUV_barycentricTri(
		surfaceST,
		(GLKVector2[3]){
			pointSTs[triInQuadIndices[0]],
			pointSTs[triInQuadIndices[1]],
			pointSTs[triInQuadIndices[2]]
		},
		(GLKVector2[3]){
			pointUVs[triInQuadIndices[0]],
			pointUVs[triInQuadIndices[1]],
			pointUVs[triInQuadIndices[2]]
		}
	);
}

static inline GLKVector2 GLKVector2FromCGPoint(CGPoint point) {
	return GLKVector2Make(point.x, point.y);
}

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
	
	const GLKVector2 texelUV = surfaceSTToTexelUV_barycentricQuad(
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
	if (self->_wrapUVs) {
		if (!WITHIN(nearestTexelXY[0], 0, self->_srcWidth - 1))
			nearestTexelXY[0] = modulo(nearestTexelXY[0], self->_srcWidth);
		if (!WITHIN(nearestTexelXY[1], 0, self->_srcHeight - 1))
			nearestTexelXY[1] = modulo(nearestTexelXY[1], self->_srcHeight);
	}
	else {
		if (!WITHIN(nearestTexelXY[0], 0, self->_srcWidth - 1))
			nearestTexelXY[0] = CLAMP(nearestTexelXY[0], 0, self->_srcWidth - 1);
		if (!WITHIN(nearestTexelXY[1], 0, self->_srcHeight - 1))
			nearestTexelXY[1] = CLAMP(nearestTexelXY[1], 0, self->_srcHeight - 1);
	}
	
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
			//byteBuffer[0] = fabsf(texelUV.x) * 255.0f; // @debug: show UVs directly
		case 1:
			byteBuffer[1] = nearestTexelSample[1];
			//byteBuffer[1] = fabsf(texelUV.y) * 255.0f; // @debug: show UVs directly
		case 2:
			byteBuffer[2] = nearestTexelSample[2];
			//byteBuffer[2] = (texelUV.x < 0 ? 127 : 0) + (texelUV.y < 0 ? 127 : 0); // @debug: show UVs directly
		case 3:
			byteBuffer[3] = nearestTexelSample[3];
			//byteBuffer[3] = 255; // @debug: show UVs directly
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
		CGFloat destScale = 0.5f;//UIScreen.mainScreen.scale;
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
	
	NSNumber *wrapUVsValue = [NSUserDefaults.standardUserDefaults objectForKey:kLastWrapUVsNameKey];
	if (wrapUVsValue == nil)
		_wrapUVs = YES;
	else
		_wrapUVs = wrapUVsValue.boolValue;
	
	NSString *srcImageName = [NSUserDefaults.standardUserDefaults stringForKey:kLastSrcImageNameKey];
	if (srcImageName == nil || ![_srcPossibilityNames containsObject:srcImageName])
		srcImageName = _srcPossibilityNames.firstObject;
	
	[self switchToImageNamed:srcImageName];
	
	self.point1 = CGPointMake(0.00f, 0.00f);
	self.point2 = CGPointMake(0.05f, 0.95f);
	self.point3 = CGPointMake(0.8f, 0.8f);
	self.point4 = CGPointMake(0.90f, 0.10f);
	
	[self.handle1 enableDragging];
	[self.handle2 enableDragging];
	[self.handle3 enableDragging];
	[self.handle4 enableDragging];
	
	[_wrapClampUVsToggleButton setTitle:nil forState:UIControlStateHighlighted];
	[_wrapClampUVsToggleButton setTitle:nil forState:UIControlStateDisabled];
	[_wrapClampUVsToggleButton setTitle:nil forState:UIControlStateSelected];
	[self updateWrapClampUVsToggleButton];
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

- (IBAction)toggleWrapClamp:(id)sender
{
	_wrapUVs = !_wrapUVs;
	[self updateWrapClampUVsToggleButton];
	[NSUserDefaults.standardUserDefaults setBool:_wrapUVs forKey:kLastWrapUVsNameKey];
	
	[self redrawDestImage];
}

- (void)updateWrapClampUVsToggleButton
{
	UIButton *wrapClampUVsToggleButton = self.wrapClampUVsToggleButton;
	
	NSString *title = _wrapUVs ? @"Wrapping UVs" : @"Clamping UVs";
	[wrapClampUVsToggleButton setTitle:title forState:UIControlStateNormal];
	
	[wrapClampUVsToggleButton sizeToFit];
	
	CGPoint center = wrapClampUVsToggleButton.center;
	center.x = self.view.bounds.size.width * 0.5f;
	wrapClampUVsToggleButton.center = center;
}

@end
