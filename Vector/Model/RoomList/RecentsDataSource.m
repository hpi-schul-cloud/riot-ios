/*
 Copyright 2015 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "RecentsDataSource.h"

#import "EventFormatter.h"

#import "VectorDesignValues.h"

#import "InviteRecentTableViewCell.h"

@interface RecentsDataSource()
{
    NSMutableArray* invitesCellDataArray;
    NSMutableArray* favoriteCellDataArray;
    NSMutableArray* conversationCellDataArray;
    NSMutableArray* lowPriorityCellDataArray;
    
    NSInteger invitesSection;
    NSInteger favoritesSection;
    NSInteger conversationSection;
    NSInteger lowPrioritySection;
    NSInteger sectionsCount;
    
    NSMutableDictionary<NSString*, id> *roomTagsListenerByUserId;
}
@end

@implementation RecentsDataSource
@synthesize onRoomInvitationReject, onRoomInvitationAccept;
@synthesize movingCellIndexPath, movingCellBackGroundView;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        // Replace event formatter
        self.eventFormatter = [[EventFormatter alloc] initWithMatrixSession:self.mxSession];
        
        favoriteCellDataArray = [[NSMutableArray alloc] init];
        conversationCellDataArray = [[NSMutableArray alloc] init];
        lowPriorityCellDataArray = [[NSMutableArray alloc] init];
        
        invitesSection = -1;
        favoritesSection = -1;
        conversationSection = -1;
        lowPrioritySection = -1;
        sectionsCount = 0;
        
        roomTagsListenerByUserId = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)removeMatrixSession:(MXSession*)matrixSession
{
    [super removeMatrixSession:matrixSession];
    
    // sanity check
    if (matrixSession && matrixSession.myUser && matrixSession.myUser.userId)
    {
        id roomTagListener = [roomTagsListenerByUserId objectForKey:matrixSession.myUser.userId];
        
        if (roomTagListener)
        {
            [self.mxSession removeListener:roomTagListener];
            [roomTagsListenerByUserId removeObjectForKey:matrixSession.myUser.userId];
        }
    }
}

- (void)dataSource:(MXKDataSource*)dataSource didStateChange:(MXKDataSourceState)aState
{
    [super dataSource:dataSource didStateChange:aState];
    
    if ((aState == MXKDataSourceStateReady) && self.mxSession && self.mxSession.myUser && self.mxSession.myUser.userId)
    {
        // Register the room tags updates to refresh the favorites order
        id roomTagsListener = [self.mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomTag]
                                                            onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {
                                                                
                                                                // Consider only live event
                                                                if (direction == MXEventDirectionForwards)
                                                                {
                                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                                        
                                                                        [self refreshRoomsSections];
                                                                        
                                                                        // And inform the delegate about the update
                                                                        [self.delegate dataSource:self didCellChange:nil];
                                                                    });
                                                                }
                                                                
                                                            }];
        
        [roomTagsListenerByUserId setObject:roomTagsListener forKey:self.mxSession.myUser.userId];
    }
}

- (void)didMXSessionInviteRoomUpdate:(NSNotification *)notif
{
    MXSession *mxSession = notif.object;
    if (mxSession == self.mxSession)
    {
        [self.delegate dataSource:self didCellChange:nil];
    }
}

#pragma mark - UITableViewDataSource

/**
 Return the header height from the section.
 */
- (CGFloat)heightForHeaderInSection:(NSInteger)section
{
    if ((section == invitesSection) || (section == favoritesSection) || (section == conversationSection) || (section == lowPrioritySection))
    {
        return 30.0f;
    }
    
    return 0.0f;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Check whether all data sources are ready before rendering recents
    if (self.state == MXKDataSourceStateReady)
    {
        // Only one section is handled by this data source.
        return sectionsCount;
    }
    return 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSUInteger count = 0;
    
    if (section == favoritesSection)
    {
        count = favoriteCellDataArray.count;
    }
    else if (section == conversationSection)
    {
        count = conversationCellDataArray.count;
    }
    else if (section == lowPrioritySection)
    {
        count = lowPriorityCellDataArray.count;
    }
    else if (section == invitesSection)
    {
        count = invitesCellDataArray.count;
    }
    
    if (self.movingCellIndexPath && (self.movingCellIndexPath.section == section))
    {
        count++;
    }

    return count;
}

- (UIView *)viewForHeaderInSection:(NSInteger)section withFrame:(CGRect)frame
{
    // add multi accounts section management
    
    if ((section == favoritesSection) || (section == conversationSection) || (section == lowPrioritySection) || (section == invitesSection))
    {
        UILabel* label = [[UILabel alloc] initWithFrame:frame];
        
        NSString* text = @"";
        
        if (section == favoritesSection)
        {
            text = NSLocalizedStringFromTable(@"room_recents_favourites", @"Vector", nil);
        }
        else if (section == conversationSection)
        {
            text = NSLocalizedStringFromTable(@"room_recents_conversations", @"Vector", nil);
        }
        else if (section == lowPrioritySection)
        {
            text = NSLocalizedStringFromTable(@"room_recents_low_priority", @"Vector", nil);
        }
        else if (section == invitesSection)
        {
            text = NSLocalizedStringFromTable(@"room_recents_invites", @"Vector", nil);
        }
    
        label.text = [NSString stringWithFormat:@"   %@", text];
        label.font = [UIFont boldSystemFontOfSize:15.0];
        label.backgroundColor = VECTOR_LIGHT_GRAY_COLOR;
        
        return label;
    }
    
    return [super viewForHeaderInSection:section withFrame:frame];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)anIndexPath
{
    NSIndexPath* indexPath = anIndexPath;
    
    if (self.movingCellIndexPath  && (self.movingCellIndexPath.section == indexPath.section))
    {
        if ([anIndexPath isEqual:self.movingCellIndexPath])
        {
            static NSString* cellIdentifier = @"VectorRecentsMovingCell";
            
            UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"VectorRecentsMovingCell"];
            
            UIImageView* imageView = [cell viewWithTag:[cellIdentifier hash]];
            
            if (!imageView || (imageView != self.movingCellBackGroundView))
            {
                if (imageView)
                {
                    [imageView removeFromSuperview];
                }
                self.movingCellBackGroundView.tag = [cellIdentifier hash];
                [cell.contentView addSubview:self.movingCellBackGroundView];
            }
            
            self.movingCellBackGroundView.frame = self.movingCellBackGroundView.frame;
            cell.contentView.backgroundColor = [UIColor greenColor];
            cell.backgroundColor = [UIColor redColor];
            
            return cell;
        }
        
        if (anIndexPath.row > self.movingCellIndexPath.row)
        {
            indexPath = [NSIndexPath indexPathForRow:anIndexPath.row-1 inSection:anIndexPath.section];
        }
    }
    
    UITableViewCell* cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    
    // on invite cell, add listeners on accept / reject buttons
    if (cell && [cell isKindOfClass:[InviteRecentTableViewCell class]])
    {
        id<MXKRecentCellDataStoring> roomData = [self cellDataAtIndexPath:indexPath];
        InviteRecentTableViewCell* inviteRecentTableViewCell = (InviteRecentTableViewCell*)cell;
        
        inviteRecentTableViewCell.onRejectClick = ^(){
            if (self.onRoomInvitationReject)
            {
                self.onRoomInvitationReject(roomData.roomDataSource.room);
            }
        };
        
        inviteRecentTableViewCell.onJoinClick = ^(){
            if (self.onRoomInvitationAccept)
            {
                self.onRoomInvitationAccept(roomData.roomDataSource.room);
            }
        };
    }
    
    return cell;
}

- (id<MXKRecentCellDataStoring>)cellDataAtIndexPath:(NSIndexPath *)anIndexPath
{
    id<MXKRecentCellDataStoring> cellData = nil;
    NSInteger row = anIndexPath.row;
    NSInteger section = anIndexPath.section;
    
    if (self.movingCellIndexPath  && (self.movingCellIndexPath.section == section))
    {
        if (anIndexPath.row > self.movingCellIndexPath.row)
        {
            row = anIndexPath.row - 1;
        }
    }
    
    if (section == favoritesSection)
    {
        cellData = [favoriteCellDataArray objectAtIndex:row];
    }
    else if (section== conversationSection)
    {
        cellData = [conversationCellDataArray objectAtIndex:row];
    }
    else if (section == lowPrioritySection)
    {
        cellData = [lowPriorityCellDataArray objectAtIndex:row];
    }
    else if (section == invitesSection)
    {
        cellData = [invitesCellDataArray objectAtIndex:row];
    }
    
    return cellData;
}

- (CGFloat)cellHeightAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.movingCellIndexPath && [indexPath isEqual:self.movingCellIndexPath])
    {
        return self.movingCellBackGroundView.frame.size.height;
    }
    
    // Override this method here to use our own cellDataAtIndexPath
    id<MXKRecentCellDataStoring> cellData = [self cellDataAtIndexPath:indexPath];
    
    if (cellData && self.delegate)
    {
        Class<MXKCellRendering> class = [self.delegate cellViewClassForCellData:cellData];
        
        return [class heightForCellData:cellData withMaximumWidth:0];
    }

    return 0;
}

- (NSInteger)cellIndexPosWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)matrixSession within:(NSMutableArray*)cellDataArray
{
    if (roomId && matrixSession && cellDataArray.count)
    {
        for (int index = 0; index < cellDataArray.count; index++)
        {
            id<MXKRecentCellDataStoring> cellDataStoring = [cellDataArray objectAtIndex:index];

            if ([roomId isEqualToString:cellDataStoring.roomDataSource.roomId] && (matrixSession == cellDataStoring.roomDataSource.mxSession))
            {
                return index;
            }
        }
    }

    return NSNotFound;
}

- (NSIndexPath*)cellIndexPathWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)matrixSession
{
    NSIndexPath *indexPath = nil;
    NSInteger index = NSNotFound;
    
    if (!indexPath && (invitesSection >= 0))
    {
        index = [self cellIndexPosWithRoomId:roomId andMatrixSession:matrixSession within:invitesCellDataArray];
        
        if (index != NSNotFound)
        {
            indexPath = [NSIndexPath indexPathForRow:index inSection:invitesSection];
        }
    }
    
    if (!indexPath && (favoritesSection >= 0))
    {
        index = [self cellIndexPosWithRoomId:roomId andMatrixSession:matrixSession within:favoriteCellDataArray];
        
        if (index != NSNotFound)
        {
            indexPath = [NSIndexPath indexPathForRow:index inSection:favoritesSection];
        }
    }
    
    if (!indexPath && (conversationSection >= 0))
    {
        index = [self cellIndexPosWithRoomId:roomId andMatrixSession:matrixSession within:conversationCellDataArray];
        
        if (index != NSNotFound)
        {
            indexPath = [NSIndexPath indexPathForRow:index inSection:conversationSection];
        }
    }
    
    if (!indexPath && (lowPrioritySection >= 0))
    {
        index = [self cellIndexPosWithRoomId:roomId andMatrixSession:matrixSession within:lowPriorityCellDataArray];
        
        if (index != NSNotFound)
        {
            indexPath = [NSIndexPath indexPathForRow:index inSection:lowPrioritySection];
        }
    }
    
    if (!indexPath)
    {
        indexPath = [super cellIndexPathWithRoomId:roomId andMatrixSession:matrixSession];
    }
    
    return indexPath;
}


#pragma mark - MXKDataSourceDelegate

// create an array filled with NSNull and with the same size as sourceArray
- (NSMutableArray*)createEmptyArray:(NSUInteger)count
{
    NSMutableArray* array = [[NSMutableArray alloc] init];
    
    for(NSUInteger i = 0; i < count; i++)
    {
        [array addObject:[NSNull null]];
    }
    
    return array;
}

- (void)refreshRoomsSections
{
    // FIXME manage multi accounts
    
    favoriteCellDataArray = [[NSMutableArray alloc] init];
    conversationCellDataArray = [[NSMutableArray alloc] init];
    lowPriorityCellDataArray = [[NSMutableArray alloc] init];
    
    favoritesSection = conversationSection = lowPrioritySection = invitesSection = -1;
    sectionsCount = 0;

    if (displayedRecentsDataSourceArray.count > 0)
    {
        MXKSessionRecentsDataSource *recentsDataSource = [displayedRecentsDataSourceArray objectAtIndex:0];
        MXSession* session = recentsDataSource.mxSession;
        
        NSArray* sortedInvitesRooms = [session invitedRooms];
        NSArray* sortedFavRooms = [session roomsWithTag:kMXRoomTagFavourite];
        NSArray* sortedLowPriorRooms = [session roomsWithTag:kMXRoomTagLowPriority];
        
        invitesCellDataArray = [self createEmptyArray:sortedInvitesRooms.count];
        favoriteCellDataArray = [self createEmptyArray:sortedFavRooms.count];
        lowPriorityCellDataArray = [self createEmptyArray:sortedLowPriorRooms.count];
        
        NSInteger count = recentsDataSource.numberOfCells;
        
        for(int index = 0; index < count; index++)
        {
            NSUInteger pos;
            id<MXKRecentCellDataStoring> recentCellDataStoring = [recentsDataSource cellDataAtIndex:index];
            MXRoom* room = recentCellDataStoring.roomDataSource.room;

            if ((pos = [sortedFavRooms indexOfObject:room]) != NSNotFound)
            {
                if (pos < favoriteCellDataArray.count)
                {
                    [favoriteCellDataArray replaceObjectAtIndex:pos withObject:recentCellDataStoring];
                }
            }
            else  if ((pos = [sortedLowPriorRooms indexOfObject:room]) != NSNotFound)
            {
                if (pos < lowPriorityCellDataArray.count)
                {
                    [lowPriorityCellDataArray replaceObjectAtIndex:pos withObject:recentCellDataStoring];
                }
            }
            else  if ((pos = [sortedInvitesRooms indexOfObject:room]) != NSNotFound)
            {
                if (pos < invitesCellDataArray.count)
                {
                    [invitesCellDataArray replaceObjectAtIndex:pos withObject:recentCellDataStoring];
                }
            }
            else
            {
                [conversationCellDataArray addObject:recentCellDataStoring];
            }
        }
        
        int sectionIndex = 0;
        
        [invitesCellDataArray removeObject:[NSNull null]];
        if (invitesCellDataArray.count > 0)
        {
            invitesSection = sectionIndex;
            sectionIndex++;
        }
        
        [favoriteCellDataArray removeObject:[NSNull null]];
        if (favoriteCellDataArray.count > 0)
        {
            favoritesSection = sectionIndex;
            sectionIndex++;
        }
        
        [conversationCellDataArray removeObject:[NSNull null]];
        if (conversationCellDataArray.count > 0)
        {
            conversationSection = sectionIndex;
            sectionIndex++;
        }
        
        [lowPriorityCellDataArray removeObject:[NSNull null]];
        if (lowPriorityCellDataArray.count > 0)
        {
            lowPrioritySection = sectionIndex;
            sectionIndex++;
        }
        
        sectionsCount = sectionIndex;
    }
}

- (void)dataSource:(MXKDataSource*)dataSource didCellChange:(id)changes
{
    // FIXME : manage multi accounts
    // to manage multi accounts
    // this method in MXKInterleavedRecentsDataSource must be split in two parts
    // 1 - the intervealing cells method
    // 2 - [super dataSource:dataSource didCellChange:changes] call.
    // the [self refreshRoomsSections] call should be done at the end of the 1- method
    // so a dedicated method must be implemented in MXKInterleavedRecentsDataSource
    // this class will inherit of this new method
    // 1 - call [super thisNewMethod]
    // 2 - call [self refreshRoomsSections]
    
    // refresh the 
    [self refreshRoomsSections];
    
    // Call super to keep update readyRecentsDataSourceArray.
    [super dataSource:dataSource didCellChange:changes];
}

#pragma mark - Override MXKDataSource

- (void)destroy
{
    [super destroy];
}


#pragma mark - drag and drop managemenent

- (BOOL)isDraggableCellAt:(NSIndexPath*)path
{
    return (path && ((path.section == favoritesSection) || (path.section == lowPrioritySection) || (path.section == conversationSection)));
}

- (BOOL)canCellMoveFrom:(NSIndexPath*)oldPath to:(NSIndexPath*)newPath
{
    BOOL res = [self isDraggableCellAt:oldPath] && [self isDraggableCellAt:newPath];
    
    // the both index pathes are movable
    if (res)
    {
        // cannot move conversation rooms in the same section
        res &= !((oldPath.section == conversationSection) && (newPath.section == conversationSection));
        
        // other cases ?
    }
    
    return res;
}

- (NSString*)roomTagAt:(NSIndexPath*)path
{
    if (path.section == favoritesSection)
    {
        return kMXRoomTagFavourite;
    }
    else if (path.section == lowPrioritySection)
    {
        return kMXRoomTagLowPriority;
    }
    
    return nil;
}

- (void)moveCellFrom:(NSIndexPath*)oldPath to:(NSIndexPath*)newPath
{
    NSLog(@"[RecentsDataSource] moveCellFrom (%d, %d) to (%d, %d)", oldPath.section, oldPath.row, newPath.section, newPath.row);
    
    if ([self canCellMoveFrom:oldPath to:newPath] && ![newPath isEqual:oldPath])
    {
        NSString* oldRoomTag = [self roomTagAt:oldPath];
        NSString* dstRoomTag = [self roomTagAt:newPath];
        
        MXRoom* room = [self getRoomAtIndexPath:oldPath];
        
        NSString* tagOrder = [room.mxSession tagOrderToBeAtIndex:newPath.row withTag:dstRoomTag];
        
        NSLog(@"[RecentsDataSource] Update the room %@ tag from %@ to %@ with tag order %@", room.state.roomId, oldRoomTag, dstRoomTag, tagOrder);
        
        [room replaceTag:oldRoomTag
                   byTag:dstRoomTag
               withOrder:tagOrder
                 success: ^{
                     
                     // Refresh table display
                     if (self.delegate)
                     {
                         [self.delegate dataSource:self didCellChange:nil];
                     }
                     
                 } failure:^(NSError *error) {
                     
                     NSLog(@"[RecentsDataSource] Failed to update the tag %@ of room (%@) failed: %@", dstRoomTag, room.state.roomId, error);
                     
                     // Notify MatrixKit user
                     [[NSNotificationCenter defaultCenter] postNotificationName:kMXKErrorNotification object:error];
                 }];
    }
    else
    {
        NSLog(@"[RecentsDataSource] cannot move this cell");
    }
}

@end
