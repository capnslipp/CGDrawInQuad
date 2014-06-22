#import <UIKit/UIKit.h>



@interface OutlineView : UIView

@property (copy, readonly, nonatomic) NSArray *points;

- (id)objectAtIndexedSubscript:(NSUInteger)idx;
- (CGPoint)pointAtIndexedSubscript:(NSUInteger)idx;

- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)idx;
- (void)setPoint:(CGPoint)point atIndexedSubscript:(NSUInteger)idx;


@property (copy, nonatomic) UIColor *lineColor;
@property (nonatomic) CGFloat lineWidth;

@end
