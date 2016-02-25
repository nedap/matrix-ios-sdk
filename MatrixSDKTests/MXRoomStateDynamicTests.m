/*
 Copyright 2014 OpenMarket Ltd
 
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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXRoomStateDynamicTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;

    MXSession *mxSession;
}
@end

@implementation MXRoomStateDynamicTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    if (mxSession)
    {
        [matrixSDKTestsData closeMXSession:mxSession];
        mxSession = nil;
    }
    [super tearDown];
}

/*
 Creates a room with the following historic.
 This scenario plays with a basic state event: m.room.topic.
 
 0 - Bob creates a private room
 1 - ... (random events generated by the home server)
 2 - Bob: "Hello world"
 3 - Bob changes the room topic to "Topic #1"
 4 - Bob: "Hola"
 5 - Bob changes the room topic to "Topic #2"
 6 - Bob: "Bonjour"
 */
-(void)createScenario1:(MXRestClient*)bobRestClient inRoom:(NSString*)roomId onComplete:(void(^)())onComplete
{
    __block MXRestClient *bobRestClient2 = bobRestClient;
    
    [bobRestClient sendTextMessageToRoom:roomId text:@"Hello world" success:^(NSString *eventId) {
        
        [bobRestClient setRoomTopic:roomId topic:@"Topic #1" success:^{
            
            [bobRestClient2 sendTextMessageToRoom:roomId text:@"Hola" success:^(NSString *eventId) {
                
                __block MXRestClient *bobRestClient3 = bobRestClient2;
                [bobRestClient2 setRoomTopic:roomId topic:@"Topic #2" success:^{
                    
                    [bobRestClient3 sendTextMessageToRoom:roomId text:@"Bonjour" success:^(NSString *eventId) {
                        
                        onComplete();
                        
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                    }];
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
        
    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
    }];
}

- (void)testBackPaginationForScenario1
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createScenario1:bobRestClient inRoom:roomId onComplete:^{
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            
            [mxSession start:^{
                
                MXRoom *room = [mxSession roomWithRoomId:roomId];
                
                __block NSUInteger eventCount = 0;
                [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                    
                    // Check each expected event and their roomState contect
                    // Events are received in the reverse order
                    switch (eventCount++) {
                        case 0:
                            // 6 - Bob: "Bonjour"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssert([roomState.topic isEqualToString:@"Topic #2"], @"roomState.topic is wrong. Found: %@", roomState.topic);
                            XCTAssert([room.state.topic isEqualToString:@"Topic #2"]);
                            break;
                            
                        case 1:
                            //  5 - Bob changes the room topic to "Topic #2"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);
                            
                            XCTAssert([roomState.topic isEqualToString:@"Topic #1"], @"roomState.topic is wrong. Found: %@", roomState.topic);
                            XCTAssert([room.state.topic isEqualToString:@"Topic #2"]);
                            break;
                            
                        case 2:
                            //  4 - Bob: "Hola"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssert([roomState.topic isEqualToString:@"Topic #1"], @"roomState.topic is wrong. Found: %@", roomState.topic);
                            XCTAssert([room.state.topic isEqualToString:@"Topic #2"]);
                            break;
                            
                        case 3:
                            //  3 - Bob changes the room topic to "Topic #1"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);
                            
                            XCTAssertNil(roomState.topic, @"The room topic was undefined before getting this event. Found: %@", roomState.topic);
                            XCTAssert([room.state.topic isEqualToString:@"Topic #2"]);
                            break;
                            
                        case 4:
                            //  2 - Bob: "Hello World"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssertNil(roomState.topic, @"The room topic was undefined before getting this event. Found: %@", roomState.topic);
                            XCTAssert([room.state.topic isEqualToString:@"Topic #2"]);
                            break;
                            
                        default:
                            break;
                    }
                    
                }];
                
                [room.liveTimeline resetPagination];
                [room.liveTimeline paginate:10 direction:MXEventDirectionBackwards onlyFromStore:NO complete:^{
                    
                    XCTAssertGreaterThan(eventCount, 4, @"We must have received events");
                    
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        }];
        
    }];
}

- (void)testLiveEventsForScenario1
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            __block NSUInteger eventCount = 0;
            [room.liveTimeline listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                // Check each expected event and their roomState contect
                // Events are live. Then comes in order
                switch (eventCount++) {

                    case 0:
                        //  2 - Bob: "Hello World"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                        
                        XCTAssertNotNil(roomState);
                        
                        XCTAssertNil(roomState.topic, @"The room topic is not yet defined. Found: %@", roomState.topic);
                        XCTAssertNil(room.state.topic, @"The room topic is not yet defined. Found: %@", roomState.topic);
                        break;
                        
                    case 1:
                        //  3 - Bob changes the room topic to "Topic #1"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);

                        XCTAssertNotNil(roomState);

                        XCTAssertNil(roomState.topic, @"The room topic was not yet defined before this event. Found: %@", roomState.topic);
                        XCTAssert([room.state.topic isEqualToString:@"Topic #1"]);
                        break;
                        
                    case 2:
                        //  4 - Bob: "Hola"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);

                        XCTAssertNotNil(roomState);

                        XCTAssert([roomState.topic isEqualToString:@"Topic #1"], @"roomState.topic is wrong. Found: %@", roomState.topic);
                        XCTAssert([room.state.topic isEqualToString:@"Topic #1"]);
                        break;
                        
                    case 3:
                        //  5 - Bob changes the room topic to "Topic #2"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomTopic);

                        XCTAssertNotNil(roomState);

                        XCTAssertEqualObjects(roomState.topic, @"Topic #1", @"roomState.topic is wrong. Found: %@", roomState.topic);
                        XCTAssert([room.state.topic isEqualToString:@"Topic #2"]);
                        break;
                        
                    case 4:
                        // 6 - Bob: "Bonjour"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);

                        XCTAssertNotNil(roomState);

                        XCTAssert([roomState.topic isEqualToString:@"Topic #2"], @"roomState.topic is wrong. Found: %@", roomState.topic);
                        XCTAssert([room.state.topic isEqualToString:@"Topic #2"]);
                        
                        // No more events. This is the end of the test
                        [expectation fulfill];
                        break;

                    default:
                        XCTFail(@"No more events are expected");
                        break;
                }
                
            }];
            
            // Send events of the scenario
            [self createScenario1:bobRestClient inRoom:roomId onComplete:^{
                
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}


/*
 Creates a room with the following historic.
 This scenario plays with m.room.member events.
 
 0 - Bob creates a private room
 1 - ... (random events generated by the home server)
 2 - Bob: "Hello World"
 3 - Bob invites Alice
 4 - Bob: "I wait for Alice"
 5 - Alice joins
 6 - Alice: "Hi"
 7 - Alice changes her displayname to "Alice in Wonderland"
 8 - Alice: "What's going on?"
 9 - Alice leaves the room
 10 - Bob: "Good bye"
 */
- (void)createScenario2:(MXRestClient*)bobRestClient inRoom:(NSString*)roomId onComplete:(void(^)(MXRestClient *aliceRestClient))onComplete
{
    [bobRestClient sendTextMessageToRoom:roomId text:@"Hello world" success:^(NSString *eventId) {
        
        MatrixSDKTestsData *sharedData = matrixSDKTestsData;
        
        [sharedData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {
            
            [bobRestClient inviteUser:sharedData.aliceCredentials.userId toRoom:roomId success:^{
                
                [bobRestClient sendTextMessageToRoom:roomId text:@"I wait for Alice" success:^(NSString *eventId) {
                    
                    [aliceRestClient joinRoom:roomId success:^(NSString *roomName){
                        
                        [aliceRestClient sendTextMessageToRoom:roomId text:@"Hi" success:^(NSString *eventId) {

                            MXRestClient *aliceRestClient2 = aliceRestClient;

                            [aliceRestClient setDisplayName:@"Alice in Wonderland" success:^{
                                
                                [aliceRestClient2 sendTextMessageToRoom:roomId text:@"What's going on?" success:^(NSString *eventId) {
                                    
                                    [bobRestClient leaveRoom:roomId success:^{
                                        
                                        [aliceRestClient2 sendTextMessageToRoom:roomId text:@"Good bye" success:^(NSString *eventId) {
                                            
                                            onComplete(aliceRestClient2);
                                            
                                        } failure:^(NSError *error) {
                                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                                        }];
                                        
                                    } failure:^(NSError *error) {
                                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                                    }];
                                    
                                } failure:^(NSError *error) {
                                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                                }];
                                
                            } failure:^(NSError *error) {
                                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                            }];
                            
                        } failure:^(NSError *error) {
                            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                        }];
                        
                    } failure:^(NSError *error) {
                        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                   }];
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    } failure:^(NSError *error) {
        NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
    }];
}

/*
- (void)testBackPaginationForScenario2
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        [self createScenario2:bobRestClient inRoom:roomId onComplete:^(MXRestClient *aliceRestClient) {
            
            mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
            
            [mxSession start:^{
                
                MXRoom *room = [mxSession roomWithRoomId:roomId];

                NSAssert(room, @"The room is required");

                __block NSUInteger eventCount = 0;
                [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                    NSLog(@"eventCount: %tu - %@", eventCount, event);
                    
                    MXRoomMember *beforeEventAliceMember = [roomState memberWithUserId:aliceRestClient.credentials.userId];
                    MXRoomMember *aliceMember = [room.state memberWithUserId:aliceRestClient.credentials.userId];
                    
                    // Check each expected event and their roomState contect
                    // Events are received in the reverse order
                    switch (eventCount++) {
                            
                        case 0:
                            // 10 - Bob: "Good bye"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssertEqual(roomState.members.count, 2);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipLeave);
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            
                            // Alice is no more part of the room. The home server does not provide her display name
                            XCTAssertNil(beforeEventAliceMember.displayname);
                            XCTAssertNil(aliceMember.displayname);
                            break;
                            
                        case 1:
                            // 9 - Alice leaves the room
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                            
                            XCTAssertEqual(roomState.members.count, 2);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            
                            XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"Alice in Wonderland"]);
                            XCTAssertNil(aliceMember.displayname);
                            break;
                            
                        case 2:
                            // 8 - Alice: "What's going on?"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssertEqual(roomState.members.count, 2);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            
                            XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"Alice in Wonderland"]);
                            XCTAssertNil(aliceMember.displayname);
                            break;
                            
                        case 3:
                            // 7 - Alice changes her displayname to "Alice in Wonderland"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                            
                            XCTAssertEqual(roomState.members.count, 2);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            
                            XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"mxAlice"], @"Wrong displayname. Found: %@", beforeEventAliceMember.displayname);
                            XCTAssertNil(aliceMember.displayname);
                            break;
                            
                        case 4:
                            // 6 - Alice: "Hi"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssertEqual(roomState.members.count, 2);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            
                            XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"mxAlice"], @"Wrong displayname. Found: %@", beforeEventAliceMember.displayname);
                            XCTAssertNil(aliceMember.displayname);
                            break;
                            
                        case 5:
                            // 5 - Alice joins
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                            
                            XCTAssertEqual(roomState.members.count, 2);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipInvite);
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            
                            // Alice was not yet part of the room. The home server does not provide her display name
                            XCTAssertNil(beforeEventAliceMember.displayname);
                            XCTAssertNil(aliceMember.displayname);
                            break;
                            
                        case 6:
                            // 4 - Bob: "I wait for Alice"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssertEqual(roomState.members.count, 2);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipInvite);
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            
                            XCTAssertNil(beforeEventAliceMember.displayname);
                            XCTAssertNil(aliceMember.displayname);
                            break;
                            
                        case 7:
                            // 3 - Bob invites Alice
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                            
                            XCTAssertEqual(roomState.members.count, 1);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            XCTAssertNil(aliceMember.displayname);
                            
                            // Alice member did not exist at that time
                            XCTAssertNil(beforeEventAliceMember);
                            break;
                            
                        case 8:
                            // 2 - Bob: "Hello World"
                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                            
                            XCTAssertEqual(roomState.members.count, 1);
                            XCTAssertEqual(room.state.members.count, 2);
                            
                            XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                            XCTAssertNil(aliceMember.displayname);
                            
                            // Alice member did not exist at that time
                            XCTAssertNil(beforeEventAliceMember);
                            break;
                            
                        default:
                            break;
                    }
                    
                }];
                
                [room.liveTimeline resetPagination];
                [room.liveTimeline paginate:2 direction:MXEventDirectionBackwards0 complete:^{
                    
                    XCTAssertGreaterThan(eventCount, 8, @"We must have received events");
                    
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        }];
        
    }];
}

- (void)testLiveEventsForScenario2
{
    MatrixSDKTestsData *sharedData = matrixSDKTestsData;
    
    [sharedData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            __block NSUInteger eventCount = 0;
            [room listenToEventsOfTypes:nil onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
                
                MXRoomMember *beforeEventAliceMember = [roomState memberWithUserId:sharedData.aliceCredentials.userId];
                MXRoomMember *aliceMember = [room.state memberWithUserId:sharedData.aliceCredentials.userId];
                
                // Check each expected event and their roomState contect
                // Events are live. Then comes in order
                switch (eventCount++) {
                        
                    case 0:
                        // 2 - Bob: "Hello World"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                        
                        XCTAssertEqual(roomState.members.count, 1);
                        XCTAssertEqual(room.state.members.count, 1);
                        
                        // Alice member doest not exist at that time
                        XCTAssertNil(beforeEventAliceMember);
                        XCTAssertNil(aliceMember);
                        break;
                        
                    case 1:
                        // 3 - Bob invites Alice
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                        
                        XCTAssertEqual(roomState.members.count, 1);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(aliceMember.membership, MXMembershipInvite);
                        XCTAssertNil(aliceMember.displayname);
                        
                        // Alice member did not exist at that time
                        XCTAssertNil(beforeEventAliceMember);
                        break;
                        
                    case 2:
                        // 4 - Bob: "I wait for Alice"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                        
                        XCTAssertEqual(roomState.members.count, 2);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipInvite);
                        XCTAssertEqual(aliceMember.membership, MXMembershipInvite);
                        
                        XCTAssertNil(beforeEventAliceMember.displayname);
                        XCTAssertNil(aliceMember.displayname);
                        break;
                        
                    case 3:
                        // 5 - Alice joins
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                        
                        XCTAssertEqual(roomState.members.count, 2);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipInvite);
                        XCTAssertEqual(aliceMember.membership, MXMembershipJoin);
                        
                        // Alice was not yet part of the room. The home server does not provide her display name
                        XCTAssertNil(beforeEventAliceMember.displayname);
                        XCTAssert([aliceMember.displayname isEqualToString:@"mxAlice"]);
                        break;
                        
                    case 4:
                        // 6 - Alice: "Hi"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                        
                        XCTAssertEqual(roomState.members.count, 2);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                        XCTAssertEqual(aliceMember.membership, MXMembershipJoin);
                        
                        XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"mxAlice"], @"Wrong displayname. Found: %@", beforeEventAliceMember.displayname);
                        XCTAssert([aliceMember.displayname isEqualToString:@"mxAlice"], @"Wrong displayname. Found: %@", beforeEventAliceMember.displayname);
                        break;
                        
                    case 5:
                        // 7 - Alice changes her displayname to "Alice in Wonderland"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                        
                        XCTAssertEqual(roomState.members.count, 2);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                        XCTAssertEqual(aliceMember.membership, MXMembershipJoin);
                        
                        XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"mxAlice"], @"Wrong displayname. Found: %@", beforeEventAliceMember.displayname);
                        XCTAssert([aliceMember.displayname isEqualToString:@"Alice in Wonderland"]);
                        break;
                        
                    case 6:
                        // 8 - Alice: "What's going on?"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                        
                        XCTAssertEqual(roomState.members.count, 2);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                        XCTAssertEqual(aliceMember.membership, MXMembershipJoin);
                        
                        XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"Alice in Wonderland"]);
                        XCTAssert([aliceMember.displayname isEqualToString:@"Alice in Wonderland"]);
                        break;
                        
                    case 7:
                        // 9 - Alice leaves the room
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMember);
                        
                        XCTAssertEqual(roomState.members.count, 2);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipJoin);
                        XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                        
                        XCTAssert([beforeEventAliceMember.displayname isEqualToString:@"Alice in Wonderland"]);
                        XCTAssertNil(aliceMember.displayname);
                        break;
                        
                    case 8:
                        // 10 - Bob: "Good bye"
                        XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                        
                        XCTAssertEqual(roomState.members.count, 2);
                        XCTAssertEqual(room.state.members.count, 2);
                        
                        XCTAssertEqual(beforeEventAliceMember.membership, MXMembershipLeave);
                        XCTAssertEqual(aliceMember.membership, MXMembershipLeave);
                        
                        // Alice is no more part of the room. The home server does not provide her display name
                        XCTAssertNil(beforeEventAliceMember.displayname);
                        XCTAssertNil(aliceMember.displayname);
                        
                        // No more events. This is the end of the test
                        [expectation fulfill];
                        
                        break;
                        
                    default:
                        XCTFail(@"No more events are expected");
                        break;
                }
                
            }];
            
            // Send events of the scenario
            [self createScenario2:bobRestClient inRoom:roomId onComplete:^(MXRestClient *aliceRestClient) {
                
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}
*/

@end
