#import "OutlineView.h"

#import <CoreGraphics/CoreGraphics.h>



@interface OutlineView () {
	CGPoint *_points;
	NSUInteger _pointCount;
	
	CGPathRef _path;
	BOOL _needsPathUpdate;
	
	CGAffineTransform _pointToScreenCoordTransform;
}

@property (nonatomic) CGPathRef path;
@property (readonly, nonatomic) CGAffineTransform pointToScreenCoordTransform;

@end


@implementation OutlineView

@synthesize lineColor=_lineColor, lineWidth=_lineWidth;
@synthesize pointToScreenCoordTransform=_pointToScreenCoordTransform;

- (UIColor *)lineColor {
	if (_lineColor == nil)
		_lineColor = self.tintColor;
	
	return _lineColor;
}
- (CGFloat)lineWidth {
	if (_lineWidth == 0.0f)
		_lineWidth = 1.0f;
	
	return _lineWidth;
}

- (void)regenPointToScreenCoordTransform
{
	CGRect bounds = self.bounds;
	CGAffineTransform newTransform = CGAffineTransformMakeScale(bounds.size.width, bounds.size.height);
	//newTransform = CGAffineTransformTranslate(newTransform, bounds.origin.x, bounds.origin.y); // necessary?
	_pointToScreenCoordTransform = newTransform;
}

- (void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];
	
	[self regenPointToScreenCoordTransform];
}

- (void)setNeedsPathUpdate {
	_needsPathUpdate = YES;
}

- (CGPathRef)path
{
	if (_path == nil)
		_needsPathUpdate = YES;
	
	if (_needsPathUpdate) {
		CGMutablePathRef newPath = CGPathCreateMutable();
		
		CGAffineTransform transform = self.pointToScreenCoordTransform;
		CGPathAddLines(newPath, &transform, _points, _pointCount);
		CGPathCloseSubpath(newPath);
		
		CGPathRelease(_path);
		_path = newPath;
		_needsPathUpdate = NO;
	}
	return _path;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	
	[self initSuperOverrides];
	[self regenPointToScreenCoordTransform];
	
	return self;
}

- (void)awakeFromNib
{
	[self initSuperOverrides];
	[self regenPointToScreenCoordTransform];
}

- (void)dealloc
{
	free(_points);
	_points = NULL;
}

- (NSArray *)points
{
	NSMutableArray *pointValueArray = [NSMutableArray arrayWithCapacity:_pointCount];
	for (int pointI = 0; pointI < _pointCount; ++pointI)
		pointValueArray[pointI] = [NSValue valueWithCGPoint:_points[pointI]];
	
	return pointValueArray;
}

- (id)objectAtIndexedSubscript:(NSUInteger)idx
{
	if (idx >= _pointCount) {
		[NSException raise:NSRangeException
			format:@"Given index (%lu) is out of range; must be less than %lu.",
				(unsigned long)idx, (unsigned long)_pointCount
		];
	}
	
	CGPoint point = _points[idx];
	return [NSValue valueWithCGPoint:point];
}

- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)idx
{
	CGPoint point = ((NSValue *)obj).CGPointValue;
	
	if (idx < _pointCount) {
		_points[idx] = point;
		
		[self setNeedsPathUpdate];
		[self setNeedsDisplay];
	}
	else if (idx == _pointCount) {
		NSUInteger newPointCount = _pointCount + 1;
		_points = realloc(_points, sizeof(CGPoint) * newPointCount);
		
		_points[idx] = point;
		
		_pointCount = newPointCount;
		
		[self setNeedsPathUpdate];
		[self setNeedsDisplay];
	}
	else {
		[NSException raise:NSRangeException
			format:@"Given index (%lu) is out of range; must be no higher than %lu.",
				(unsigned long)idx, (unsigned long)_pointCount
		];
	}
}

- (void)drawRect:(CGRect)rect
{
	if (_pointCount == 0)
		return;
	
	CGContextRef context = UIGraphicsGetCurrentContext();
	
	CGRect boundsRect = self.bounds;
	BOOL isDrawRectAPortionOfBounds = !CGRectEqualToRect(CGRectIntersection(boundsRect, rect), boundsRect);
	if (isDrawRectAPortionOfBounds)
		CGContextClipToRect(context, rect);
	
	CGContextAddPath(context, self.path);
	
	[self.lineColor setStroke];
	CGContextSetLineWidth(context, self.lineWidth);
	CGContextSetLineDash(context, 0, (CGFloat[2]){ 2.0f, 3.0f }, 2);
	CGContextStrokePath(context);
}

- (void)initSuperOverrides
{
	super.clearsContextBeforeDrawing = [self clearsContextBeforeDrawing];
	super.opaque = [self opaque];
	super.backgroundColor = [self backgroundColor];
}

- (BOOL)clearsContextBeforeDrawing { return YES; }
- (void)setClearsContextBeforeDrawing:(BOOL)clearsContextBeforeDrawing {}

- (BOOL)opaque { return NO; }
- (void)setOpaque:(BOOL)opaque {}

- (UIColor *)backgroundColor { return nil; }
- (void)setBackgroundColor:(UIColor *)backgroundColor {}

@end
