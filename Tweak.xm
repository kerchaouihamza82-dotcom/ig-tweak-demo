#import <Foundation/Foundation.h>

// Demo para clase - v0.0.14
// Version ESTABLE: solo la rotacion de nombres en la audiencia
// (España se inserta arriba, valores intactos). Sin hooks de UI.

#define IGDEMO_TAG "[IGDEMO]"

static void igdemo_log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%s %@", IGDEMO_TAG, msg);
}

static BOOL igdemo_stringMentionsSpain(NSString *s) {
    return [s containsString:@"España"] || [s containsString:@"EspaÃ±a"] || [s containsString:@"Spain"];
}

static BOOL igdemo_stringMentionsMexico(NSString *s) {
    return [s containsString:@"México"] || [s containsString:@"MÃ©xico"] || [s containsString:@"Mexico"];
}

static NSRegularExpression *igdemo_pctRegex() {
    static NSRegularExpression *re;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\d+(?:[.,]\\d+)?\\s*%\\s*$" options:0 error:nil];
    });
    return re;
}

static BOOL igdemo_isPurePct(NSString *s) {
    return [igdemo_pctRegex() firstMatchInString:s options:0 range:NSMakeRange(0, s.length)] != nil;
}

static void igdemo_setInParent(id parent, id key, id value) {
    @try {
        if ([parent isKindOfClass:[NSMutableDictionary class]]) {
            [(NSMutableDictionary *)parent setObject:value forKey:key];
        } else if ([parent isKindOfClass:[NSMutableArray class]]) {
            [(NSMutableArray *)parent replaceObjectAtIndex:[key unsignedIntegerValue] withObject:value];
        }
    } @catch (NSException *e) {}
}

@interface IGDemoNode : NSObject
@property (strong) id parent;
@property (strong) id key;
@property (strong) NSString *s;
@property (strong) NSArray *path;
@end
@implementation IGDemoNode
@end

static NSMutableArray<IGDemoNode *> *g_nodos = nil;

static void igdemo_scanNode(id obj, id parent, id key, NSMutableArray *path) {
    if (path.count > 60) return;

    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in [(NSDictionary *)obj allKeys]) {
            [path addObject:k];
            igdemo_scanNode(obj[k], obj, k, path);
            [path removeLastObject];
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        for (NSUInteger i = 0; i < arr.count; i++) {
            [path addObject:@(i)];
            igdemo_scanNode(arr[i], (NSMutableArray *)arr, @(i), path);
            [path removeLastObject];
        }
    } else if ([obj isKindOfClass:[NSString class]]) {
        IGDemoNode *n = [IGDemoNode new];
        n.parent = parent;
        n.key = key;
        n.s = obj;
        n.path = [path copy];
        [g_nodos addObject:n];
    }
}

static NSInteger igdemo_lcaDepth(NSArray *a, NSArray *b) {
    NSInteger k = 0, n = MIN(a.count, b.count);
    while (k < n && [a[k] isEqual:b[k]]) k++;
    return k;
}

static NSString *igdemo_huellaPadre(IGDemoNode *n) {
    if (![n.parent isKindOfClass:[NSDictionary class]]) return @"<no-dict>";
    NSArray *ks = [(NSDictionary *)n.parent allKeys];
    NSMutableArray *copias = [NSMutableArray arrayWithArray:ks];
    [copias sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [[NSString stringWithFormat:@"%@", a] compare:[NSString stringWithFormat:@"%@", b]];
    }];
    return [copias componentsJoinedByString:@"|"];
}

static void igdemo_procesaEspana(id parsed) {
    g_nodos = [NSMutableArray array];
    igdemo_scanNode(parsed, nil, nil, [NSMutableArray array]);

    IGDemoNode *nameE = nil, *nameM = nil;
    for (IGDemoNode *n in g_nodos) {
        if (igdemo_isPurePct(n.s) || n.s.length >= 40) continue;
        if (!nameE && igdemo_stringMentionsSpain(n.s)) nameE = n;
        if (!nameM && igdemo_stringMentionsMexico(n.s)) nameM = n;
    }

    if (!nameE || !nameM) {
        g_nodos = nil;
        return;
    }

    NSString *claveTexto = [NSString stringWithFormat:@"%@", nameE.key];
    NSString *huella = igdemo_huellaPadre(nameE);
    NSMutableArray<IGDemoNode *> *candidatos = [NSMutableArray array];
    for (IGDemoNode *n in g_nodos) {
        if (igdemo_isPurePct(n.s) || n.s.length >= 40) continue;
        if (![[NSString stringWithFormat:@"%@", n.key] isEqualToString:claveTexto]) continue;
        if (![igdemo_huellaPadre(n) isEqualToString:huella]) continue;
        [candidatos addObject:n];
    }

    NSInteger umbral = igdemo_lcaDepth(nameE.path, nameM.path);
    NSInteger idxE = -1;
    for (NSUInteger i = 0; i < candidatos.count; i++) {
        if (candidatos[i] == nameE) { idxE = (NSInteger)i; break; }
    }
    if (idxE < 0) { g_nodos = nil; return; }

    NSInteger lo = idxE, hi = idxE;
    while (lo - 1 >= 0 && igdemo_lcaDepth(candidatos[lo - 1].path, candidatos[lo].path) >= umbral) lo--;
    while (hi + 1 < (NSInteger)candidatos.count && igdemo_lcaDepth(candidatos[hi + 1].path, candidatos[hi].path) >= umbral) hi++;

    NSMutableArray<IGDemoNode *> *escalones = [NSMutableArray array];
    for (NSInteger i = lo; i <= hi; i++) [escalones addObject:candidatos[i]];

    BOOL tieneMexico = NO;
    for (IGDemoNode *n in escalones) if (n == nameM) tieneMexico = YES;
    if (escalones.count < 2 || !tieneMexico) { g_nodos = nil; return; }

    NSMutableArray<NSString *> *nuevos = [NSMutableArray array];
    [nuevos addObject:nameE.s];
    for (IGDemoNode *n in escalones) {
        if (n != nameE) [nuevos addObject:n.s];
    }

    NSMutableArray<NSString *> *antes = [NSMutableArray array];
    NSMutableArray<NSString *> *despues = [NSMutableArray array];
    for (NSUInteger i = 0; i < escalones.count; i++) {
        [antes addObject:escalones[i].s];
        [despues addObject:nuevos[i]];
        if (![escalones[i].s isEqualToString:nuevos[i]]) {
            igdemo_setInParent(escalones[i].parent, escalones[i].key, nuevos[i]);
        }
    }

    igdemo_log(@">>> ROTACION: [%@] -> [%@]",
               [antes componentsJoinedByString:@", "],
               [despues componentsJoinedByString:@", "]);
    g_nodos = nil;
}

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opts error:(NSError **)error {
    @try {
        if (!data || data.length < 16) return %orig;

        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        BOOL pareceAudience = raw && ([raw containsString:@"audience"] || [raw containsString:@"demograph"] ||
                                      igdemo_stringMentionsSpain(raw) || igdemo_stringMentionsMexico(raw));
        if (!pareceAudience) return %orig;

        NSError *tmpErr = nil;
        id parsed = %orig(data, (opts | NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves), &tmpErr);
        if (!parsed) return %orig;

        igdemo_procesaEspana(parsed);
        return parsed;
    } @catch (NSException *e) {
        igdemo_log(@"excepcion: %@", e);
        return %orig;
    }
}
%end

%ctor {
    %init;
    igdemo_log(@"tweak v0.0.14 (solo Espana, estable) cargado en %@", [[NSBundle mainBundle] bundleIdentifier]);
}
