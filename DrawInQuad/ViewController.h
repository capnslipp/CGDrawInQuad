#import <UIKit/UIKit.h>

#import "OutlineView.h"

#import "QBPopupMenu.h"


@interface ViewController : UIViewController <QBPopupMenuDelegate>

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet OutlineView *outlineView;

@property (weak, nonatomic) IBOutlet UIButton *handle1;
@property (weak, nonatomic) IBOutlet UIButton *handle2;
@property (weak, nonatomic) IBOutlet UIButton *handle3;
@property (weak, nonatomic) IBOutlet UIButton *handle4;
- (IBAction)draggedHandle:(id)sender;

@property (nonatomic) CGPoint point1;
@property (nonatomic) CGPoint point2;
@property (nonatomic) CGPoint point3;
@property (nonatomic) CGPoint point4;

@property (weak, nonatomic) IBOutlet UIButton *imageSelectionButton;
- (IBAction)selectImage:(id)sender;

@property (weak, nonatomic) IBOutlet UIButton *wrapClampUVsToggleButton;
- (IBAction)toggleWrapClamp:(id)sender;

- (IBAction)redrawNow:(id)sender;

@end
