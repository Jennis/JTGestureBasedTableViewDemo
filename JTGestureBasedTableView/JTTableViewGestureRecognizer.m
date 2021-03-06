/*
 * This file is part of the JTGestureBasedTableView package.
 * (c) James Tang <mystcolor@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "JTTableViewGestureRecognizer.h"

typedef enum {
    JTTableViewGestureRecognizerStateNone,
    JTTableViewGestureRecognizerStateDragging,
    JTTableViewGestureRecognizerStatePinching,
    JTTableViewGestureRecognizerStatePanning,
} JTTableViewGestureRecognizerState;

CGFloat const JTTableViewCommitEditingRowDefaultLength = 80;

@interface JTTableViewGestureRecognizer () <UIGestureRecognizerDelegate>
@property (nonatomic, assign) id <JTTableViewGestureAddingRowDelegate, JTTableViewGestureEditingRowDelegate> delegate;
@property (nonatomic, assign) id <UITableViewDelegate>   tableViewDelegate;
@property (nonatomic, assign) UITableView               *tableView;
@property (nonatomic, assign) CGFloat                    addingRowHeight;
@property (nonatomic, retain) NSIndexPath               *addingIndexPath;
@property (nonatomic, assign) JTTableViewCellEditingState  addingCellState;
@property (nonatomic, assign) CGPoint                    startPinchingUpperPoint;
@property (nonatomic, retain) UIPinchGestureRecognizer  *pinchRecognizer;
@property (nonatomic, retain) UIPanGestureRecognizer    *panRecognizer;
@property (nonatomic, assign) JTTableViewGestureRecognizerState state;

- (void)commitOrDiscardCell;

@end

@implementation JTTableViewGestureRecognizer
@synthesize delegate, tableView, tableViewDelegate;
@synthesize addingIndexPath, startPinchingUpperPoint, addingRowHeight;
@synthesize pinchRecognizer, panRecognizer;
@synthesize state, addingCellState;

#pragma mark Logic

- (void)commitOrDiscardCell {
    UITableViewCell *cell = (UITableViewCell *)[self.tableView cellForRowAtIndexPath:self.addingIndexPath];
    [self.tableView beginUpdates];
    
    
    CGFloat commitingCellHeight = self.tableView.rowHeight;
    if ([self.delegate respondsToSelector:@selector(heightForCommittingRowForGestureRecognizer:)]) {
        commitingCellHeight = [self.delegate heightForCommittingRowForGestureRecognizer:self];
    }
    
    if (cell.frame.size.height >= commitingCellHeight) {
        [self.delegate gestureRecognizer:self needsCommitRowAtIndexPath:self.addingIndexPath];
    } else {
        [self.delegate gestureRecognizer:self needsDiscardRowAtIndexPath:self.addingIndexPath];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:self.addingIndexPath] withRowAnimation:UITableViewRowAnimationMiddle];
    }
    self.addingIndexPath = nil;
    [self.tableView endUpdates];
    
    // Restore contentInset while touch ends
    [UIView beginAnimations:@"" context:nil];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [UIView setAnimationDuration:0.5];  // Should not be less than the duration of row animation 
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
    [UIView commitAnimations];
    
    self.state = JTTableViewGestureRecognizerStateNone;
}

#pragma mark Action

- (void)pinchGestureRecognizer:(UIPinchGestureRecognizer *)recognizer {
//    NSLog(@"%d %f %f", [recognizer numberOfTouches], [recognizer velocity], [recognizer scale]);
    if (recognizer.state == UIGestureRecognizerStateEnded || [recognizer numberOfTouches] < 2) {
        if (self.addingIndexPath) {
            [self commitOrDiscardCell];
        }
        return;
    }
    
    CGPoint location1 = [recognizer locationOfTouch:0 inView:self.tableView];
    CGPoint location2 = [recognizer locationOfTouch:1 inView:self.tableView];
    CGPoint upperPoint = location1.y < location2.y ? location1 : location2;
    
    CGRect  rect = (CGRect){location1, location2.x - location1.x, location2.y - location1.y};
    
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.state = JTTableViewGestureRecognizerStatePinching;

        NSArray *indexPaths = [self.tableView indexPathsForRowsInRect:rect];
        
        NSIndexPath *firstIndexPath = [indexPaths objectAtIndex:0];
        NSIndexPath *lastIndexPath  = [indexPaths lastObject];
        NSInteger    midIndex = ((float)(firstIndexPath.row + lastIndexPath.row) / 2) + 0.5;
        NSIndexPath *midIndexPath = [NSIndexPath indexPathForRow:midIndex inSection:firstIndexPath.section];
        
        // Setting up properties for referencing later when touches changes
        self.startPinchingUpperPoint = upperPoint;
        
        if ([self.delegate respondsToSelector:@selector(gestureRecognizer:willCreateCellAtIndexPath:)]) {
           self.addingIndexPath = [self.delegate gestureRecognizer:self willCreateCellAtIndexPath:midIndexPath];
        } else {
            self.addingIndexPath = midIndexPath;
        }
        
        // Creating contentInset to fulfill the whole screen, so our tableview won't occasionaly
        // bounds back to the top while we don't have enough cells on the screen
        self.tableView.contentInset = UIEdgeInsetsMake(self.tableView.frame.size.height, 0, self.tableView.frame.size.height, 0);

        if (self.addingIndexPath) {
            [self.tableView beginUpdates];
            
            [self.delegate gestureRecognizer:self needsAddRowAtIndexPath:self.addingIndexPath];

            [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:self.addingIndexPath] withRowAnimation:UITableViewRowAnimationMiddle];
            [self.tableView endUpdates];
        }
        
    } else if (recognizer.state == UIGestureRecognizerStateChanged) {
        
        CGFloat diffRowHeight = CGRectGetHeight(rect) - CGRectGetHeight(rect)/[recognizer scale];
        
//        NSLog(@"%f %f %f", CGRectGetHeight(rect), CGRectGetHeight(rect)/[recognizer scale], [recognizer scale]);
        if (self.addingRowHeight - diffRowHeight >= 1 || self.addingRowHeight - diffRowHeight <= -1) {
            self.addingRowHeight = diffRowHeight;
            [self.tableView reloadData];
        }
        
        // Scrolls tableview according to the upper touch point to mimic a realistic
        // dragging gesture
        CGPoint newUpperPoint = upperPoint;
        CGFloat diffOffsetY = self.startPinchingUpperPoint.y - newUpperPoint.y;
        CGPoint newOffset   = (CGPoint){self.tableView.contentOffset.x, self.tableView.contentOffset.y+diffOffsetY};
        [self.tableView setContentOffset:newOffset animated:NO];
    }
}

- (void)panGestureRecognizer:(UIPanGestureRecognizer *)recognizer {
    if ((recognizer.state == UIGestureRecognizerStateBegan
        || recognizer.state == UIGestureRecognizerStateChanged)
        && [recognizer numberOfTouches] > 0) {

        // TODO: should ask delegate before changing cell's content view

        CGPoint location1 = [recognizer locationOfTouch:0 inView:self.tableView];
        
        NSIndexPath *indexPath = self.addingIndexPath;
        if ( ! indexPath) {
            indexPath = [self.tableView indexPathForRowAtPoint:location1];
            self.addingIndexPath = indexPath;
        }
        
        self.state = JTTableViewGestureRecognizerStatePanning;
        
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];

        CGPoint translation = [recognizer translationInView:self.tableView];
        cell.contentView.frame = CGRectOffset(cell.contentView.bounds, translation.x, 0);

        if ([self.delegate respondsToSelector:@selector(gestureRecognizer:didChangeContentViewTranslation:forRowAtIndexPath:)]) {
            [self.delegate gestureRecognizer:self didChangeContentViewTranslation:translation forRowAtIndexPath:indexPath];
        }
        
        CGFloat commitEditingLength = JTTableViewCommitEditingRowDefaultLength;
        if ([self.delegate respondsToSelector:@selector(gestureRecognizer:lengthForCommitEditingRowAtIndexPath:)]) {
            commitEditingLength = [self.delegate gestureRecognizer:self lengthForCommitEditingRowAtIndexPath:indexPath];
        }
        if (fabsf(translation.x) >= commitEditingLength) {
            if (self.addingCellState == JTTableViewCellEditingStateMiddle) {
                self.addingCellState = translation.x > 0 ? JTTableViewCellEditingStateRight : JTTableViewCellEditingStateLeft;
            }
        } else {
            if (self.addingCellState != JTTableViewCellEditingStateMiddle) {
                self.addingCellState = JTTableViewCellEditingStateMiddle;
            }
        }

        if ([self.delegate respondsToSelector:@selector(gestureRecognizer:didEnterEditingState:forRowAtIndexPath:)]) {
            [self.delegate gestureRecognizer:self didEnterEditingState:self.addingCellState forRowAtIndexPath:indexPath];
        }

    } else if (recognizer.state == UIGestureRecognizerStateEnded) {

        NSIndexPath *indexPath = self.addingIndexPath;

        // Removes addingIndexPath before updating then tableView will be able
        // to determine correct table row height
        self.addingIndexPath = nil;

        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        CGPoint translation = [recognizer translationInView:self.tableView];
        
        CGFloat commitEditingLength = JTTableViewCommitEditingRowDefaultLength;
        if ([self.delegate respondsToSelector:@selector(gestureRecognizer:lengthForCommitEditingRowAtIndexPath:)]) {
            commitEditingLength = [self.delegate gestureRecognizer:self lengthForCommitEditingRowAtIndexPath:indexPath];
        }
        if (fabsf(translation.x) >= commitEditingLength) {
            if ([self.delegate respondsToSelector:@selector(gestureRecognizer:commitEditingState:forRowAtIndexPath:)]) {
                [self.delegate gestureRecognizer:self commitEditingState:self.addingCellState forRowAtIndexPath:indexPath];
            }
        } else {
            [UIView beginAnimations:@"" context:nil];
            cell.contentView.frame = cell.contentView.bounds;
            [UIView commitAnimations];
        }
        
        self.addingCellState = JTTableViewCellEditingStateMiddle;
        self.state = JTTableViewGestureRecognizerStateNone;
    }
}

#pragma mark UIGestureRecognizer

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {

    if (gestureRecognizer == self.panRecognizer) {
        if ( ! [self.delegate conformsToProtocol:@protocol(JTTableViewGestureEditingRowDelegate)]) {
            return NO;
        }
        
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        
        CGPoint point = [pan translationInView:self.tableView];
        CGPoint location = [pan locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];

        // The pan gesture recognizer will fail the original scrollView scroll
        // gesture, we wants to ensure we are panning left/right to enable the
        // pan gesture.
        if (fabsf(point.y) > fabsf(point.x)) {
            return NO;
        } else if (indexPath == nil) {
            return NO;
        } else if (indexPath) {
            BOOL canEditRow = [self.delegate gestureRecognizer:self canEditRowAtIndexPath:indexPath];
            return canEditRow;
        }
    } else if (gestureRecognizer == self.pinchRecognizer) {
        if ( ! [self.delegate conformsToProtocol:@protocol(JTTableViewGestureAddingRowDelegate)]) {
            NSLog(@"Should not begin pinch");
            return NO;
        }
    }
    return YES;
}

#pragma mark UITableViewDelegate

- (CGFloat)tableView:(UITableView *)aTableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath isEqual:self.addingIndexPath]) {
        return MAX(1, self.addingRowHeight);
    }
    
    CGFloat normalCellHeight = aTableView.rowHeight;
    if ([self.tableViewDelegate respondsToSelector:@selector(tableView:heightForRowAtIndexPath:)]) {
        normalCellHeight = [self.tableViewDelegate tableView:aTableView heightForRowAtIndexPath:indexPath];
    }
    return normalCellHeight;
}

#pragma mark UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if ( ! [self.delegate conformsToProtocol:@protocol(JTTableViewGestureAddingRowDelegate)]) {
        if ([self.tableViewDelegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
            [self.tableViewDelegate scrollViewDidScroll:scrollView];
        }
        return;
    }

    // We try to create a new cell when the user tries to drag the content to and offset of negative value
    if (scrollView.contentOffset.y < 0) {
        // Here we make sure we're not conflicting with the pinch event,
        // ! scrollView.isDecelerating is to detect if user is actually
        // touching on our scrollView, if not, we should assume the scrollView
        // needed not to be adding cell
        if ( ! self.addingIndexPath && self.state == JTTableViewGestureRecognizerStateNone && ! scrollView.isDecelerating) {
            self.state = JTTableViewGestureRecognizerStateDragging;

            self.addingIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
            if ([self.delegate respondsToSelector:@selector(gestureRecognizer:willCreateCellAtIndexPath:)]) {
                self.addingIndexPath = [self.delegate gestureRecognizer:self willCreateCellAtIndexPath:self.addingIndexPath];
            }

            [self.tableView beginUpdates];
            [self.delegate gestureRecognizer:self needsAddRowAtIndexPath:self.addingIndexPath];
            [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:self.addingIndexPath] withRowAnimation:UITableViewRowAnimationNone];
            self.addingRowHeight = fabsf(scrollView.contentOffset.y);
            [self.tableView endUpdates];
        }
    }
    
    if (self.state == JTTableViewGestureRecognizerStateDragging) {
//        NSLog(@"%@", NSStringFromCGPoint(scrollView.contentOffset));
        self.addingRowHeight += scrollView.contentOffset.y * -1;
        [self.tableView reloadData];
        [scrollView setContentOffset:CGPointZero];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if ( ! [self.delegate conformsToProtocol:@protocol(JTTableViewGestureAddingRowDelegate)]) {
        if ([self.tableViewDelegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
            [self.tableViewDelegate scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
        }
        return;
    }

    if (self.state == JTTableViewGestureRecognizerStateDragging) {
        self.state = JTTableViewGestureRecognizerStateNone;
        [self commitOrDiscardCell];
    }
}

#pragma mark NSProxy

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    [anInvocation invokeWithTarget:self.tableViewDelegate];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [(NSObject *)self.tableViewDelegate methodSignatureForSelector:aSelector];
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    NSAssert(self.tableViewDelegate != nil, @"self.tableViewDelegate should not be nil, assign your tableView.delegate before enabling gestureRecognizer", nil);
    if ([self.tableViewDelegate respondsToSelector:aSelector]) {
        return YES;
    }
    return [[self class] instancesRespondToSelector:aSelector];
}

#pragma mark Class method

+ (JTTableViewGestureRecognizer *)gestureRecognizerWithTableView:(UITableView *)tableView delegate:(id)delegate {
    JTTableViewGestureRecognizer *recognizer = [[JTTableViewGestureRecognizer alloc] init];
    recognizer.delegate             = (id)delegate;
    recognizer.tableView            = tableView;
    recognizer.tableViewDelegate    = tableView.delegate;     // Assign the delegate before chaning the tableView's delegate
    tableView.delegate              = recognizer;
    
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:recognizer action:@selector(pinchGestureRecognizer:)];
    [tableView addGestureRecognizer:pinch];
    pinch.delegate             = recognizer;
    recognizer.pinchRecognizer = pinch;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:recognizer action:@selector(panGestureRecognizer:)];
    [tableView addGestureRecognizer:pan];
    pan.delegate             = recognizer;
    recognizer.panRecognizer = pan;

    return recognizer;
}

@end


@implementation UITableView (JTTableViewGestureDelegate)

- (JTTableViewGestureRecognizer *)enableGestureTableViewWithDelegate:(id)delegate {
    if ( ! [delegate conformsToProtocol:@protocol(JTTableViewGestureAddingRowDelegate)] && ! [delegate conformsToProtocol:@protocol(JTTableViewGestureEditingRowDelegate)]) {
        [NSException raise:@"delegate should at least conform to one of JTTableViewGestureAddingRowDelegate or JTTableViewGestureEditingRowDelegate" format:nil];
    }
    JTTableViewGestureRecognizer *recognizer = [JTTableViewGestureRecognizer gestureRecognizerWithTableView:self delegate:delegate];
    return recognizer;
}

@end