#import <UIKit/UIKit.h>

#import "OutlineView.h"



@interface ViewController : UIViewController

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet OutlineView *outlineView;

@property (weak, nonatomic) IBOutlet UIButton *handle1;
@property (weak, nonatomic) IBOutlet UIButton *handle2;
@property (weak, nonatomic) IBOutlet UIButton *handle3;
@property (weak, nonatomic) IBOutlet UIButton *handle4;

@property (nonatomic) CGPoint point1;
@property (nonatomic) CGPoint point2;
@property (nonatomic) CGPoint point3;
@property (nonatomic) CGPoint point4;


- (IBAction)draggedHandle:(id)sender;

@end
