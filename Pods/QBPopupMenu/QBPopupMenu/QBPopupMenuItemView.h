//
//  QBPopupMenuItemView.h
//  QBPopupMenu
//
//  Created by Tanaka Katsuma on 2013/11/22.
//  Copyright (c) 2013年 Katsuma Tanaka. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QBPopupMenu;
@class QBPopupMenuItem;

@interface QBPopupMenuItemView : UIView

@property (nonatomic, weak, readonly) QBPopupMenu *popupMenu;

@property (nonatomic, strong, readonly) UIButton *button;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIImage *highlightedImage;

@property (nonatomic, strong) QBPopupMenuItem *item;

+ (instancetype)itemViewForMenu:(QBPopupMenu *)popupMenu withItem:(QBPopupMenuItem *)item;
- (instancetype)initForMenu:(QBPopupMenu *)popupMenu withItem:(QBPopupMenuItem *)item;

- (void)performAction;

@end
