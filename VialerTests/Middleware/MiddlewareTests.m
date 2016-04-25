//
//  MiddlewareTests.m
//  Copyright © 2016 VoIPGRID. All rights reserved.
//

#import "APNSHandler.h"
#import "Configuration.h"
#import "Middleware.h"
#import "MiddlewareRequestOperationManager.h"
#import <OCMock/OCMock.h>
#import <OHHTTPStubs/OHHTTPStubs.h>
#import "ReachabilityManager.h"
#import "SystemUser.h"
@import XCTest;

@interface Middleware()
@property (strong, nonatomic) MiddlewareRequestOperationManager *middlewareRequestOperationManager;
@property (strong, nonatomic) ReachabilityManager *reachabilityManager;
@property (weak, nonatomic) SystemUser *systemUser;
@end

@interface MiddlewareTests : XCTestCase
@property (strong, nonatomic) Middleware *middleware;
@end

@implementation MiddlewareTests

- (void)setUp {
    [super setUp];
    self.middleware = [[Middleware alloc] init];
}

- (void)tearDown {
    self.middleware = nil;
    [super tearDown];
}

- (void)testSystemUserGetterCreation {
    SystemUser *sharedCurrentUser = [SystemUser currentUser];
    SystemUser *APNSHandlerPropertyOfSystemUser = self.middleware.systemUser;

    XCTAssertEqualObjects(sharedCurrentUser, APNSHandlerPropertyOfSystemUser, @"System User - Current User instances did not match");
}

- (void)testMiddlewareRequestOperationManagerPropertyCreation {
    MiddlewareRequestOperationManager *createdMiddlewareRequestOperationManager = self.middleware.middlewareRequestOperationManager;

    XCTAssert([createdMiddlewareRequestOperationManager isKindOfClass:[MiddlewareRequestOperationManager class]]);

    NSString *baseURLFromConfig = [[Configuration defaultConfiguration] UrlForKey:ConfigurationMiddleWareBaseURLString];
    XCTAssert([[createdMiddlewareRequestOperationManager.baseURL absoluteString] isEqualToString:baseURLFromConfig], @"Base URL of the API endpoint did not match %@ and %@", createdMiddlewareRequestOperationManager.baseURL.absoluteString, baseURLFromConfig);

    XCTAssert([createdMiddlewareRequestOperationManager.responseSerializer isKindOfClass:[AFHTTPResponseSerializer class]]);

    NSSet *referenceSet = [NSSet setWithObjects:@"GET", @"HEAD", nil];
    XCTAssert([createdMiddlewareRequestOperationManager.requestSerializer.HTTPMethodsEncodingParametersInURI isEqualToSet:referenceSet],
              @"Only GET and HEAD parameters should be put in URI, the rest in body");
}

- (void)testReachabilityManagerCreation {
    //The Assert calls the getter which will lazy load de registry which succeeds the test.
    XCTAssert([self.middleware.reachabilityManager isKindOfClass:[ReachabilityManager class]]);
}

- (void)testSentAPNSToken {
    //Given
    id mockMiddlewareRequestOperationManager = OCMClassMock([MiddlewareRequestOperationManager class]);
    id mockSystemUser = OCMClassMock([SystemUser class]);
    NSString *mockAPNSToken = @"0000000011111111222222223333333344444444555555556666666677777777";
    NSString *mockSIPAccount = @"012334456";

    //When
    self.middleware.middlewareRequestOperationManager = mockMiddlewareRequestOperationManager;
    OCMStub([mockSystemUser sipEnabled]).andReturn(YES);
    OCMStub([mockSystemUser sipAccount]).andReturn(mockSIPAccount);
    self.middleware.systemUser = mockSystemUser;
    [self.middleware sentAPNSToken:mockAPNSToken];

    //Then
    OCMVerify([mockMiddlewareRequestOperationManager updateDeviceRecordWithAPNSToken:[OCMArg isEqual:mockAPNSToken] sipAccount:[OCMArg isEqual:mockSIPAccount] withCompletion:[OCMArg any]]);
    [mockMiddlewareRequestOperationManager stopMocking];
    [mockSystemUser stopMocking];
}

@end