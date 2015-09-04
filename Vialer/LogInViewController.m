//
//  LogInViewController.m
//  Vialer
//
//  Created by Reinier Wieringa on 06/11/13.
//  Copyright (c) 2014 VoIPGRID. All rights reserved.
//

#import "LogInViewController.h"
#import "VoIPGRIDRequestOperationManager.h"
#import "ConnectionHandler.h"
#import "UIAlertView+Blocks.h"
#import "SVProgressHUD.h"
#import "UIView+RoundedStyle.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#import "AnimatedImageView.h"
#import "VIAScene.h"

#import "AppDelegate.h"

#import "PBWebViewController.h"

#define SHOW_LOGIN_ALERT      100
#define PASSWORD_FORGOT_ALERT 101

@interface LogInViewController ()
@property (nonatomic, assign) BOOL alertShown;
@property (nonatomic, strong) NSString *user;
@end

@implementation LogInViewController {
    BOOL _isKeyboardShown;
    VIAScene *_scene;
    
    __block NSUInteger _fetchAccountRetryCount;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UITapGestureRecognizer *tg = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(deselectAllTextFields:)];
    [self.view addGestureRecognizer:tg];
    
    _fetchAccountRetryCount = 0;
    
    self.logoView.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    
    // animate logo to top
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self moveLogoOutOfScreen];
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self removeObservers];
}

- (UIStatusBarStyle) preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

/**
 * Deselect all textfields when a user taps somewhere in the view.
 */
- (void)deselectAllTextFields:(UITapGestureRecognizer*)recognizer {
    [self.loginFormView.usernameField resignFirstResponder];
    [self.loginFormView.passwordField resignFirstResponder];
    [self.configureFormView.phoneNumberField resignFirstResponder];
    [self.forgotPasswordView.emailTextfield resignFirstResponder];
}

/**
 * clears all text field contents from all views
 */
- (void)clearAllTextFields {
    self.loginFormView.usernameField.text = nil;
    self.loginFormView.passwordField.text = nil;
    self.configureFormView.phoneNumberField.text = nil;
    self.configureFormView.outgoingNumberLabel.text = nil;
    self.forgotPasswordView.emailTextfield.text = nil;
}

#pragma mark - UIView lifecycle methods.
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self clearAllTextFields];
    [self addObservers];
}

/* 
 - Set all keyboard types and return keys for the textFields when the view did appear.
 - Furthermore create login flow through the Return key.
 */
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Set type to emailAddress for e-mail field for forgot password steps
    //Done in Interface builder [self.forgotPasswordView.emailTextfield setKeyboardType:UIKeyboardTypeEmailAddress];
    //Done in Interface builder[self.forgotPasswordView.emailTextfield setReturnKeyType:UIReturnKeySend];
    self.forgotPasswordView.requestPasswordButton.enabled = NO;
    
    //to be able/disable the enable the request password button
    [self.forgotPasswordView.emailTextfield addTarget:self action:@selector(forgotPasswordViewTextFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    
    // Set phone number input settings for outgoing and fallback call numbers.
    //Done in Interface builder [self.configureFormView.phoneNumberField setKeyboardType:UIKeyboardTypeNumbersAndPunctuation];
    //Done in Interface builder [self.configureFormView.phoneNumberField setReturnKeyType:UIReturnKeySend];
    
    // Make text field react to Enter to login!
    [self.loginFormView setTextFieldDelegate:self];
    [self.configureFormView setTextFieldDelegate:self];
    [self.forgotPasswordView.emailTextfield setDelegate:self];
}

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    self.alertShown = NO;
}

#pragma mark - UITextField delegate methods
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([self.loginFormView.usernameField isEqual:textField]) {
        // TODO: focus on password field
        [textField resignFirstResponder];
        [self.loginFormView.passwordField becomeFirstResponder];
    } else if ([self.loginFormView.passwordField isEqual:textField]) {
        NSString *username = [self.loginFormView.usernameField text];
        NSString *password = [self.loginFormView.passwordField text];
        if ([username length] > 0 && [password length] > 0) {
            [self continueFromLoginFormViewToConfigureFormView];
            return YES;
        } else {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No login data", nil)
                                        message:NSLocalizedString(@"Enter Your email address and password to login.", nil)
                                       delegate:self
                              cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                              otherButtonTitles:nil]
             show];
            self.alertShown = YES;
            return NO;
        }
    } else if ([self.configureFormView.phoneNumberField isEqual:textField]) {
        [textField resignFirstResponder];
        [self continueFromConfigureFormViewToUnlockView];
        return YES;
    } else if ([self.forgotPasswordView.emailTextfield isEqual:textField]) {
        NSString *emailRegEx = @"[A-Z0-9a-z\\._%+-]+@([A-Za-z0-9-]+\\.)+[A-Za-z]{2,4}";
        if ([[NSPredicate predicateWithFormat:@"SELF MATCHES %@", emailRegEx]
             evaluateWithObject:textField.text]) {
            [self resetPasswordWithEmail:textField.text];
            [self animateForgotPasswordViewToVisible:0.f delay:0.8];
            [self animateLoginViewToVisible:1.f delay:0.f];
            return YES;
        } else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Sorry!", nil)
                                                            message:NSLocalizedString(@"Please enter a valid email address.", nil)
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                                                  otherButtonTitles:nil];
            [alert show];
            self.alertShown = YES;
        }
    }
    return NO;
}

//Checks have been done to ensure the text fields have data, otherwise the button would not be clickable.
- (IBAction)loginButtonPushed:(UIButton *)sender {
    [self continueFromLoginFormViewToConfigureFormView];
}

- (void)forgotPasswordViewTextFieldDidChange:(UITextField *)textField {
    NSString *emailRegEx = @"[A-Z0-9a-z\\._%+-]+@([A-Za-z0-9-]+\\.)+[A-Za-z]{2,4}";
    if ([[NSPredicate predicateWithFormat:@"SELF MATCHES %@", emailRegEx]
         evaluateWithObject:textField.text])
        self.forgotPasswordView.requestPasswordButton.enabled = YES;
    else
        self.forgotPasswordView.requestPasswordButton.enabled = NO;
}

//Check for valid email is done, otherwise the button would not be enabled.
- (IBAction)requestPasswordButtonPressed:(UIButton *)sender {
    [self resetPasswordWithEmail:self.forgotPasswordView.emailTextfield.text];
}

- (IBAction)configureViewContinueButtonPressed:(UIButton *)sender {
    [self continueFromConfigureFormViewToUnlockView];
}

- (void)continueFromLoginFormViewToConfigureFormView {
    NSString *username = self.loginFormView.usernameField.text;
    NSString *password = self.loginFormView.passwordField.text;
    [self doLoginCheckWithUname:username password:password successBlock:^{
        [self retrievePhoneNumbersWithSuccessBlock:nil];
    }];
    [self deselectAllTextFields:nil];
}

- (void)continueFromConfigureFormViewToUnlockView {
    NSString *newNumber = self.configureFormView.phoneNumberField.text;
    [SVProgressHUD showWithStatus:NSLocalizedString(@"SAVING_NUMBER...", nil) maskType:SVProgressHUDMaskTypeGradient];
    
    //Force pushing the mobile number to the server. Covers the case where a user has set his mobile number in v1.x which was not pushed to server yet.
    [[VoIPGRIDRequestOperationManager sharedRequestOperationManager] pushMobileNumber:newNumber forcePush:YES success:^{
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"NUMBER_SAVED_SUCCESS", nil)];
        
        //Now that numbers have been saved, localy stored phone number and server side mobile number are in sync,
        //Migration was completed succesfully
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"v2.0_MigrationComplete"];
        
        [self.configureFormView.phoneNumberField resignFirstResponder];
        [self animateConfigureViewToVisible:0.f delay:0.f]; // Hide
        [self animateUnlockViewToVisible:1.f delay:1.5f];    // Show
        [_scene runActThree];                     // Animate the clouds
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {}];
        
    } failure:^(NSString *localizedErrorString) {
        [SVProgressHUD dismiss];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", nil)
                                                        message:localizedErrorString
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                                              otherButtonTitles:nil];
        [alert show];
    }];
}

#pragma mark Keyboard

/**
 * Add observers to check when keyboards is hidden and shown, to know when to animatie view up or down
 */
- (void)addObservers{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)removeObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification*)notification {
    if(!_isKeyboardShown) {
        NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        UIViewAnimationCurve curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];

        NSValue *keyboardRect = notification.userInfo[UIKeyboardFrameBeginUserInfoKey];
        CGFloat keyboardHeight = CGRectGetHeight([keyboardRect CGRectValue]);
        
        //After the animation, the respective view should be centered on the remaining screen height (original screen height -keyboard height)
        CGFloat remainingScreenHeight = CGRectGetHeight(self.view.frame) - keyboardHeight;
        //Divide the remaining screen height by 2, this will be the center of the displayed view
        CGFloat newCenter = lroundf(remainingScreenHeight /2);
        
        //Move the left top most cloud away to make the text visable (white on white)
        [_scene animateCloudsOutOfViewWithDuration:duration];
        
        [UIView animateWithDuration:duration
                              delay:0.0
                            options:(curve << 16)
                         animations:^{
                             //TODO: Storing the frame's center in an ivar just to be able to restore it is a bit of a hack
                             //but I could not think of a better way.
                             self.loginFormView.centerBeforeKeyboardAnimation = self.loginFormView.center;
                             self.loginFormView.center = CGPointMake(self.loginFormView.center.x, newCenter);
                             
                             self.configureFormView.centerBeforeKeyboardAnimation = self.configureFormView.center;
                             self.configureFormView.center = CGPointMake(self.configureFormView.center.x, newCenter);
                             
                             self.forgotPasswordView.centerBeforeKeyboardAnimation = self.forgotPasswordView.center;
                             self.forgotPasswordView.center = CGPointMake(self.forgotPasswordView.center.x, newCenter);
                         }
                         completion:^(BOOL finished){
                             
                         }];
        
        _isKeyboardShown = YES;
    }
}

- (void)keyboardWillHide:(NSNotification*)notification {
    if(_isKeyboardShown  && !self.alertShown) {
        NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        UIViewAnimationCurve curve = (UIViewAnimationCurve) [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
        
        [_scene animateCloudsIntoViewWithDuration:duration];
        
        [UIView animateWithDuration:duration
                              delay:0.0
                            options:(UIViewAnimationOptions) (curve << 16)
                         animations:^{
                             self.loginFormView.center = self.loginFormView.centerBeforeKeyboardAnimation;
                             self.configureFormView.center = self.configureFormView.centerBeforeKeyboardAnimation;
                             self.forgotPasswordView.center = self.forgotPasswordView.centerBeforeKeyboardAnimation;
                         }
                         completion:nil];
        
        _isKeyboardShown = NO;
    }
}

#pragma mark - Helper method that greets you when you reach the lock screen.
- (void)setLockScreenFriendlyNameWithResponse:(id)responseObject {
    if ([responseObject isKindOfClass:[NSDictionary class]]) {
        NSDictionary *userDict = (NSDictionary*)responseObject;
        NSString *firstName = userDict[@"first_name"];
        NSString *lastName = userDict[@"last_name"];
        NSString *greeting;
        if (firstName && lastName)
            greeting = [NSString stringWithFormat:@"%@ %@!", userDict[@"first_name"], userDict[@"last_name"]];

        [self.unlockView.greetingsLabel setText:greeting];
    }
}

#pragma mark - Navigation actions
- (void)moveLogoOutOfScreen { /* Act one (1) */
    // Create an animation scenes that transitions to configure view.
    // VIAScene uses view dimensions to calculate the positions of clouds, at this point the self.view is resized correctly from xib values.
    _scene = [[VIAScene alloc] initWithView:self.view];
    
    void (^logoAnimations)(void) = ^{
        [self.logoView setCenter:CGPointMake(self.logoView.center.x, -CGRectGetHeight(self.logoView.frame))];
    };
    [UIView animateWithDuration:2.2 animations:logoAnimations];
    
    switch (self.screenToShow) {
        case OnboardingScreenLogin:
            [_scene runActOne];
            break;
        case OnboardingScreenConfigure:
            [_scene runActOneInstantly];  // Remove the scene 1 clouds instantly
            [_scene runActTwo];           // Animate the clouds
            [self retrievePhoneNumbersWithSuccessBlock:nil];
            break;
//        case OnboardingScreenUnlock:
//            [_scene runActThree];
//            break;
        default:
            //Show the login screen as default
            [_scene runActOne];
            break;
    }
    
    void (^afterLogoAnimations)(void) = ^{
        switch (self.screenToShow) {
            case OnboardingScreenLogin:
                [self animateLoginViewToVisible:1.f delay:0.f]; // show
                break;
            case OnboardingScreenConfigure:
                [self animateConfigureViewToVisible:1.f delay:0.f]; // Show
                break;
//            case OnboardingScreenUnlock:
//                [self animateUnlockViewToVisible:1.f delay:0.f];
//                break;
            default:
                //Show the login screen as default
                [_scene runActOne];
                break;
        }
    };
    [UIView animateWithDuration:1.9 delay:0.f options:UIViewAnimationOptionCurveEaseOut animations:afterLogoAnimations completion:nil];
}

- (IBAction)openForgotPassword:(id)sender {
    [self.loginFormView.usernameField resignFirstResponder];
    [self.loginFormView.passwordField resignFirstResponder];
    self.forgotPasswordView.emailTextfield.text = nil;

    [self animateLoginViewToVisible:0.f delay:0.f];
    [self animateForgotPasswordViewToVisible:1.f delay:2.f];
}

- (IBAction)closeButtonPressed:(UIButton *)sender {
    [self.forgotPasswordView.emailTextfield resignFirstResponder];

    [self animateForgotPasswordViewToVisible:0.f delay:0.f];
    [self animateLoginViewToVisible:1.f delay:1.5f];
}

- (void)resetPasswordWithEmail:(NSString*)email {
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Sending email...", nil) maskType:SVProgressHUDMaskTypeGradient];
    [[VoIPGRIDRequestOperationManager sharedRequestOperationManager] passwordResetWithEmail:email success:^(AFHTTPRequestOperation *operation, id responseObject) {
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Email sent successfully.", nil)];
        
        [self animateLoginViewToVisible:1.f delay:1.f];
        [self animateForgotPasswordViewToVisible:0.f delay:0.8f];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to send email.", nil)];
        [self animateLoginViewToVisible:1.f delay:0.8f];
        [self animateForgotPasswordViewToVisible:0.f delay:0.8];
    }];
}

- (void)openConfigurationInstructions:(id)sender {
    PBWebViewController *webViewController = [[PBWebViewController alloc] init];

    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Config" ofType:@"plist"]];
    NSString *onboardingUrl = [[config objectForKey:@"URLS"] objectForKey:NSLocalizedString(@"onboarding", @"Reference to URL String in the config.plist to the localized onboarding information page")];
    webViewController.URL = [NSURL URLWithString:onboardingUrl];
    webViewController.showsNavigationToolbar = YES;
    webViewController.hidesBottomBarWhenPushed = YES;
    webViewController.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo"]];
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:webViewController];
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeConfigurationInstructions)];
    webViewController.navigationItem.rightBarButtonItem = cancelButton;
    
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)closeConfigurationInstructions {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doLoginCheckWithUname:(NSString *)username password:(NSString *)password successBlock:(void (^)())success {
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Logging in...", nil) maskType:SVProgressHUDMaskTypeGradient];
    [[VoIPGRIDRequestOperationManager sharedRequestOperationManager] loginWithUser:username password:password success:^(AFHTTPRequestOperation *operation, id responseObject) {
        [SVProgressHUD dismiss];

        //Check if a SIP account is configured to be used with the App. The app should default the the Connect A/B behaviour simular to the old App.
        if ([VoIPGRIDRequestOperationManager sharedRequestOperationManager].sipAccount) {
            [[ConnectionHandler sharedConnectionHandler] sipConnect];
        } else {
            [UIAlertView showWithTitle:@"No SIP account" message:@"No Mobile app VoIP account configured, only Connect A/B functionality provided." cancelButtonTitle:@"OK" otherButtonTitles:nil tapBlock:nil];
            //Just to make sure no sip connection is registered
            [[ConnectionHandler sharedConnectionHandler] sipDisconnect:nil];
        }
        [self setLockScreenFriendlyNameWithResponse:operation.responseObject];
        
        [self animateLoginViewToVisible:0.f delay:0.f];     // Hide
        [self animateConfigureViewToVisible:1.f delay:0.f]; // Show
        [_scene runActTwo];                       // Animate the clouds

        // When login is successfull: register with incoming call middleware to get notifications when being called
        AppDelegate *delegate = (AppDelegate*)[[UIApplication sharedApplication] delegate];
        [delegate registerForVoIPNotifications];
        
        //If a success block was provided, execute it
        if (success)
            success ();
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [SVProgressHUD dismiss];
    }];
}

- (void)retrievePhoneNumbersWithSuccessBlock:(void (^)())success {
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Retrieving phone numbers...", nil) maskType:SVProgressHUDMaskTypeGradient];
    [[VoIPGRIDRequestOperationManager sharedRequestOperationManager] userProfileWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        _fetchAccountRetryCount = 0; // Reset the retry count
        NSString *outgoingNumber = [[VoIPGRIDRequestOperationManager sharedRequestOperationManager] outgoingNumber];
        if (outgoingNumber) {
            [self.configureFormView.outgoingNumberLabel setText:outgoingNumber];
        } else {
            [self.configureFormView.outgoingNumberLabel setText:@""];
        }
        
        NSString *localStoreMobielNumber = [[NSUserDefaults standardUserDefaults] objectForKey:@"MobileNumber"];
        //Give preference to the user entered phone number over the phone number stored on the server
        if ([localStoreMobielNumber length] > 0) {
            self.configureFormView.phoneNumberField.text = localStoreMobielNumber;
        } else {
            NSString *mobile_nr = [responseObject objectForKey:@"mobile_nr"];
            //if the response also contained the mobile nr, display it to the user
            if ([mobile_nr isKindOfClass:[NSString class]]) {
                self.configureFormView.phoneNumberField.text = mobile_nr;
            }
        }
        
        [SVProgressHUD dismiss];
        
        [self setLockScreenFriendlyNameWithResponse:responseObject];
        
        //If a success block was provided, execute it
        if (success) {
            success ();
        }
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [SVProgressHUD dismiss];
        ++_fetchAccountRetryCount;
        if (_fetchAccountRetryCount != 3) { // When we retried 3 times
            [self retrievePhoneNumbersWithSuccessBlock:nil];
        } else {
            [self.configureFormView.outgoingNumberLabel setUserInteractionEnabled:YES];
            [self.configureFormView.outgoingNumberLabel setText:NSLocalizedString(@"Enter phonenumber manually", nil)];
            
            [UIAlertView showWithTitle:NSLocalizedString(@"Error", nil)
                               message:NSLocalizedString(@"Error while retrieving your outgoing number, please enter manually", nil)
                                 style:UIAlertViewStylePlainTextInput
                     cancelButtonTitle:nil
                     otherButtonTitles:@[NSLocalizedString(@"Ok", nil)]
                              tapBlock:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                  //TODO: do something with the entered number
                                  NSLog(@"outgoing number = %@", [alertView textFieldAtIndex:0].text);
                                  
                              }];

        }
    }];
}

#pragma mark - Navigation animations

- (void)animateLoginViewToVisible:(CGFloat)alpha delay:(CGFloat)delay { /* Act one (2) */
    void(^animations)(void) = ^{
        [self.loginFormView setAlpha:alpha];
    };
    void(^completion)(BOOL) = ^(BOOL finished) {
        if (alpha == 1.f) {
            [self.loginFormView.usernameField becomeFirstResponder];
        } else if (alpha == 0.f) {
            [self.loginFormView.usernameField resignFirstResponder];
        }
    };
    [UIView animateWithDuration:0.2f
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:animations
                     completion:completion];
}

- (void)animateForgotPasswordViewToVisible:(CGFloat)alpha delay:(CGFloat)delay {
    void(^animations)(void) = ^{
        [self.closeButton setAlpha:alpha];
        [self.forgotPasswordView setAlpha:alpha];
    };
    void(^completion)(BOOL) = ^(BOOL finished) {
        if (alpha == 1.f) {
            [self.forgotPasswordView.emailTextfield becomeFirstResponder];
        } else if (alpha == 0.f) {
            [self.forgotPasswordView.emailTextfield resignFirstResponder];
        }
    };
    [UIView animateWithDuration:0.8f
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:animations
                     completion:completion];
}

- (void)animateConfigureViewToVisible:(CGFloat)alpha delay:(CGFloat)delay { /* Act two */
    void(^animations)(void) = ^{
        [self.configureFormView setAlpha:alpha];
    };
    void(^completion)(BOOL) = ^(BOOL finished) {
        if (alpha == 1.f) {
            [self.configureFormView.phoneNumberField becomeFirstResponder];
        } else if (alpha == 0.f) {
            [self.configureFormView.phoneNumberField resignFirstResponder];
        }
    };
    [UIView animateWithDuration:2.2f
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:animations
                     completion:completion];
    
}

- (void)animateUnlockViewToVisible:(CGFloat)alpha delay:(CGFloat)delay { /* act three */
    void(^animations)(void) = ^{
        [self.unlockView setAlpha:alpha];
    };
    [UIView animateWithDuration:2.2f
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                     animations:animations
                     completion:^(BOOL finished) {
                         // Automatically continue after 2 seconds
                         [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(unlockIt) userInfo:nil repeats:NO];
                     }];
    
}

- (IBAction)unlockIt {
    // Put here what happens when it is unlocked
    [_scene clean];
    [self dismissViewControllerAnimated:YES completion:^{
        [self.unlockView setAlpha:0.f];
        [self.logoView setAlpha:1.f];
        [self.logoView setCenter:self.view.center];
    }];
}

@end
