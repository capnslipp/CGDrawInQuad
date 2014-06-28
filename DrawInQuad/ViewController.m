#import "ViewController.h"

#include "CGTextureMapping.h"

#include <mach/mach_time.h>
#include <dispatch/dispatch.h>

#import "UIView+draggable.h"
#import "BlocksKit.h"



#pragma mark Profiling Util Functions

/// nSec: nanoseconds
uint64_t getAccurateSystemTime_nSec()
{
	static mach_timebase_info_data_t sTimebaseInfo = {0};
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		mach_timebase_info(&sTimebaseInfo);
	});
	
	uint64_t time_nSec = mach_absolute_time() * sTimebaseInfo.numer / sTimebaseInfo.denom;
	return time_nSec;
}

static const uint64_t kNSecsPerSec = 1000000000;
static inline uint32_t nSecsToSecs(uint64_t nSecs) {
	return (uint32_t)(nSecs / kNSecsPerSec);
}
static inline uint32_t nSecsSubSecRemainder(uint64_t nSecs) {
	return (uint32_t)(nSecs % kNSecsPerSec);
}



#pragma mark Constants

static NSString *const kLastSrcImageNameKey = @"ViewController_LastSrcImageName";
static NSString *const kLastWrapUVsNameKey = @"ViewController_WrapUVsName";

static const int kComponentCount = 4;



#pragma mark Class

@interface ViewController () {
	NSArray *_srcPossibilityNames;
	
	QBPopupMenu *_popupMenu;
	
	UIImage *_srcImage;
	CFDataRef _srcData;
	int _srcWidth, _srcHeight;
	
	UIImage *_destImage;
	size_t _destByteCount;
	int _destWidth, _destHeight;
	
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

- (UIImage *)destImage
{
	if (!_destImage) {
		CGSize destBoundsSize = self.imageView.bounds.size;
		CGFloat destScale = 0.5f;//UIScreen.mainScreen.scale;
		unsigned int width = _destWidth = (destBoundsSize.width * destScale),
			height = _destHeight = (destBoundsSize.height * destScale);
		
		CGImageRef srcCGImage = _srcImage.CGImage;
		if (!_srcData) {
			_srcData = CGDataProviderCopyData(CGImageGetDataProvider(srcCGImage));
			_srcWidth = (int)CGImageGetWidth(srcCGImage);
			_srcHeight = (int)CGImageGetHeight(srcCGImage);
		}
		
		size_t bitsPerComponent = CGImageGetBitsPerComponent(srcCGImage);
		size_t bitsPerPixel = bitsPerComponent * kComponentCount;
		size_t bitsPerRow = bitsPerPixel * width,
			bytesPerRow = bitsPerRow >> 3;
		_destByteCount = bytesPerRow * height;
		
		uint64_t startTime_nSec = getAccurateSystemTime_nSec();
		
		size_t createdByteCount = 0;
		UInt8 *imageData = createDestImageData(
			_srcWidth, _srcHeight, _srcData,
			_destWidth, _destHeight,
			(CGPoint[4]){ self.point1, self.point2, self.point3, self.point4 },
			_wrapUVs,
			&createdByteCount
		);
		NSAssert(createdByteCount == _destByteCount, @"Number of bytes generated (%zu) does not match calculated total byte count (%zu).", createdByteCount, _destByteCount);
		
		// The advange of using a CFData with CGDataProviderCreateWithCFData() over CGDataProviderCreateWithData() is that the data is ref-counted, and in this function we can release-it-and-forget-it.
		// Specifically: `imageData` is now owned by `data`, which after this function's scope is owned by `dataProvider` which is owned by `destCGImage`, which is owned by `_destImage`.
		CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, imageData, createdByteCount, kCFAllocatorMalloc);
		CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData(data);
		
		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
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
		CGColorSpaceRelease(colorSpace);
		
		CGDataProviderRelease(dataProvider);
		CFRelease(data);
		
		uint64_t endTime_nSec = getAccurateSystemTime_nSec();
		
		uint64_t elapsedTime_nSec = endTime_nSec - startTime_nSec;
		uint32_t elapsedTime_subNSec = nSecsSubSecRemainder(elapsedTime_nSec),
			elapsedTime_sec = nSecsToSecs(elapsedTime_nSec);
		double elapsedTime_secD = (double)elapsedTime_sec + ((double)elapsedTime_subNSec / kNSecsPerSec);
		double elapsedTime_mSecD = elapsedTime_secD * 1000;
		printf("Redrew %d×%d in %fms.\n", width, height, elapsedTime_mSecD);
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
	
	[self redrawDestImage];
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
	
	// called as a side-effect of repositioning the wrapClampUVsToggleButton: [self redrawDestImage];
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
