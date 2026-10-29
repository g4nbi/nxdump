// NXDump - passive diagnostic tweak (ElleKit/TweakInject).
// Finds Nyxian's home screen view controller (NXHomeScreenViewController), dumps its
// ivars, methods, view tree and related classes, then copies the report to the clipboard
// and saves it to nxdump.txt. It does not modify anything.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>

static NSMutableString *O;
static BOOL gDone = NO;
static int gLines = 0;

static void L(NSString *f, ...) NS_FORMAT_FUNCTION(1, 2);
static void L(NSString *f, ...) {
    va_list a; va_start(a, f);
    NSString *s = [[NSString alloc] initWithFormat:f arguments:a];
    va_end(a);
    [O appendString:s]; [O appendString:@"\n"];
}

static NSString *ind(int d) {
    return [@"" stringByPaddingToLength:(NSUInteger)(d * 2) withString:@" " startingAtIndex:0];
}

static void dumpCls(Class c, int cap) {
    Class sup = class_getSuperclass(c);
    const char *img = class_getImageName(c);
    L(@"\nCLASS %s : %s   [%s]", class_getName(c), sup ? class_getName(sup) : "-", img ? img : "?");
    unsigned n = 0;
    Ivar *iv = class_copyIvarList(c, &n);
    for (unsigned j = 0; j < n && j < 80; j++) {
        const char *nm = ivar_getName(iv[j]); const char *ty = ivar_getTypeEncoding(iv[j]);
        L(@"  ivar %s  %s", nm ? nm : "?", ty ? ty : "?");
    }
    free(iv);
    Method *ms = class_copyMethodList(c, &n);
    for (unsigned j = 0; j < n && j < (unsigned)cap; j++) L(@"  - %s", sel_getName(method_getName(ms[j])));
    free(ms);
    ms = class_copyMethodList(object_getClass(c), &n);
    for (unsigned j = 0; j < n && j < 40; j++) L(@"  + %s", sel_getName(method_getName(ms[j])));
    free(ms);
}

static void viewTree(UIView *v, int d, int maxd) {
    if (gLines++ > 700) return;
    NSMutableString *x = [NSMutableString stringWithFormat:@"%@%@ %@", ind(d), NSStringFromClass(v.class), NSStringFromCGRect(v.frame)];
    if (v.hidden) [x appendString:@" hidden"];
    if ([v isKindOfClass:UIScrollView.class]) {
        UIScrollView *sv = (UIScrollView *)v;
        [x appendFormat:@" SCROLL content=%@ offset=%@ paging=%d enabled=%d delegate=%@",
            NSStringFromCGSize(sv.contentSize), NSStringFromCGPoint(sv.contentOffset), sv.pagingEnabled, sv.scrollEnabled,
            sv.delegate ? NSStringFromClass([(NSObject *)sv.delegate class]) : @"nil"];
    }
    if ([v isKindOfClass:UICollectionView.class]) {
        UICollectionView *cv = (UICollectionView *)v;
        [x appendFormat:@" COLLECTION layout=%@ sections=%ld", NSStringFromClass(cv.collectionViewLayout.class), (long)cv.numberOfSections];
        if ([cv.collectionViewLayout isKindOfClass:UICollectionViewFlowLayout.class])
            [x appendFormat:@" dir=%ld", (long)((UICollectionViewFlowLayout *)cv.collectionViewLayout).scrollDirection];
        if (cv.numberOfSections > 0) [x appendFormat:@" items0=%ld", (long)[cv numberOfItemsInSection:0]];
        [x appendFormat:@" dataSource=%@", cv.dataSource ? NSStringFromClass([(NSObject *)cv.dataSource class]) : @"nil"];
    }
    L(@"%@", x);
    if (d >= maxd) return;
    for (UIView *s in v.subviews) viewTree(s, d + 1, maxd);
}

static void walkVC(UIViewController *vc, int d, NSMutableArray *homes) {
    if (!vc || d > 14) return;
    NSString *n = NSStringFromClass(vc.class);
    L(@"%@VC %@ %@", ind(d), n, vc.isViewLoaded ? NSStringFromCGRect(vc.view.frame) : @"(view not loaded)");
    if ([n rangeOfString:@"HomeScreen"].location != NSNotFound) [homes addObject:vc];
    for (UIViewController *c in vc.childViewControllers) walkVC(c, d + 1, homes);
    UIViewController *p = vc.presentedViewController;
    if (p && p.presentingViewController == vc) walkVC(p, d + 1, homes);
}

static NSArray *allWindows(void) {
    NSMutableArray *a = [NSMutableArray array];
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *s in app.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) [a addObjectsFromArray:((UIWindowScene *)s).windows];
    if (!a.count && app.windows) [a addObjectsFromArray:app.windows];
    return a;
}

static void ivarValues(id obj) {
    for (Class c = object_getClass(obj); c && c != UIViewController.class && c != NSObject.class; c = class_getSuperclass(c)) {
        unsigned n = 0;
        Ivar *iv = class_copyIvarList(c, &n);
        for (unsigned j = 0; j < n; j++) {
            const char *ty = ivar_getTypeEncoding(iv[j]);
            const char *nm = ivar_getName(iv[j]);
            if (!ty || ty[0] != '@') continue;
            id v = object_getIvar(obj, iv[j]);
            NSMutableString *x = [NSMutableString stringWithFormat:@"  %s.%s = %@", class_getName(c), nm ? nm : "?", v ? NSStringFromClass([v class]) : @"nil"];
            if ([v isKindOfClass:UIView.class]) [x appendFormat:@" frame=%@", NSStringFromCGRect(((UIView *)v).frame)];
            if ([v isKindOfClass:NSArray.class]) [x appendFormat:@" count=%lu", (unsigned long)[(NSArray *)v count]];
            L(@"%@", x);
        }
        free(iv);
    }
}

static void report(NSArray *homes0, NSString *why) {
    O = [NSMutableString new];
    gLines = 0;
    L(@"NXDump: %@", why);
    L(@"process=%@ bundle=%@ iOS=%@", NSProcessInfo.processInfo.processName, NSBundle.mainBundle.bundleIdentifier, UIDevice.currentDevice.systemVersion);
    L(@"NXHomeScreenViewController class present: %d", NSClassFromString(@"NXHomeScreenViewController") != nil);

    L(@"\n== WINDOWS / VC TREE ==");
    NSMutableArray *homes = [NSMutableArray array];
    for (UIWindow *w in allWindows()) {
        L(@"WINDOW %@ %@ level=%.0f", NSStringFromClass(w.class), NSStringFromCGRect(w.frame), w.windowLevel);
        walkVC(w.rootViewController, 1, homes);
    }
    for (UIViewController *h in homes) {
        L(@"\n== HOME VC %@ ==", NSStringFromClass(h.class));
        ivarValues(h);
        dumpCls(h.class, 250);
        L(@"\n== HOME VIEW TREE ==");
        if (h.isViewLoaded) viewTree(h.view, 0, 10);
    }

    unsigned n = 0;
    Class *cs = objc_copyClassList(&n);
    L(@"\n== NON-SYSTEM CLASSES (names) ==");
    int cnt = 0, dumped = 0;
    for (unsigned i = 0; i < n; i++) {
        const char *cn = class_getName(cs[i]);
        const char *img = class_getImageName(cs[i]);
        if (!img || strncmp(img, "/System/", 8) == 0 || strncmp(img, "/usr/lib/", 9) == 0 || strstr(img, "/Cryptexes/")) continue;
        if (strncmp(cn, "FLEX", 4) == 0) continue;
        if (cnt < 400) { const char *base = strrchr(img, '/'); L(@"  %s  [%s]", cn, base ? base + 1 : img); cnt++; }
        if (dumped < 14 && (strstr(cn, "Dock") || strstr(cn, "Icon") || strstr(cn, "HomeScreen") || strstr(cn, "Pager") ||
                            strstr(cn, "Launch") || strstr(cn, "Wallpaper") || strstr(cn, "Switcher"))) {
            dumpCls(cs[i], 100); dumped++;
        }
    }
    free(cs);
}

static void emit(void) {
    NSString *s = O.length > 90000 ? [[O substringToIndex:90000] stringByAppendingString:@"\n...(cut)"] : [O copy];
    NSMutableArray *paths = [NSMutableArray arrayWithObjects:
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/nxdump.txt"],
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"nxdump.txt"],
        @"/var/mobile/Documents/nxdump.txt", nil];
    NSString *hd = NSHomeDirectory();
    NSRange r = [hd rangeOfString:@"/Library/Boot/"];
    if (r.location != NSNotFound) [paths addObject:[[hd substringToIndex:r.location] stringByAppendingString:@"/Documents/nxdump.txt"]];
    for (NSString *p in paths) [s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIPasteboard.generalPasteboard.string = s;
}

static void toast(UIView *host) {
    if (!host) return;
    UILabel *l = [UILabel new];
    l.text = @"  NXDump: report copied to clipboard  ";
    l.textColor = UIColor.whiteColor;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    l.font = [UIFont boldSystemFontOfSize:13];
    l.layer.cornerRadius = 10;
    l.clipsToBounds = YES;
    [l sizeToFit];
    l.frame = CGRectMake((host.bounds.size.width - l.bounds.size.width - 8) / 2, 60, l.bounds.size.width + 8, 30);
    [host addSubview:l];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [l removeFromSuperview]; });
}

static void tick(int n, BOOL emexlabs) {
    if (gDone) return;
    NSMutableArray *homes = [NSMutableArray array];
    O = [NSMutableString new];
    for (UIWindow *w in allWindows()) walkVC(w.rootViewController, 1, homes);
    if (homes.count) {
        gDone = YES;
        UIView *host = ((UIViewController *)homes.firstObject).viewIfLoaded;
        report(homes, @"home VC found");
        emit();
        toast(host);
        return;
    }
    if (n < 30) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ tick(n + 1, emexlabs); });
        return;
    }
    gDone = YES;
    report(@[], @"home VC NOT found (timeout)");
    emit();
}

__attribute__((constructor)) static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
        BOOL emex = [bid hasPrefix:@"org.emexlabs"];
        if (!NSClassFromString(@"NXHomeScreenViewController") && !emex) return;
        tick(0, emex);
    });
}
