#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Demo para clase - v0.0.13
// 1) Audiencia: España arriba (rotacion de nombres) - intacta.
// 2) VIEWS x5 en TODA la app: ahora en la capa de PINTADO (UILabel), que es
//    donde Instagram escribe el numero final en pantalla. Un solo x5 global
//    (cuadricula, feed, insights, todo consistente).

#define IGDEMO_TAG "[IGDEMO]"
static const double kIGDemoViewsFactor = 5.0;

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

// ---- Feature 1: rotacion de nombres (Espana arriba) ----
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

// ---- Feature 2: views x5 en la capa de pintado ----

static NSString *igdemo_miles(NSInteger n) {
    NSString *s = [NSString stringWithFormat:@"%ld", (long)n];
    NSMutableString *r = [NSMutableString string];
    NSInteger len = (NSInteger)s.length;
    for (NSInteger i = 0; i < len; i++) {
        [r appendFormat:@"%@", [s substringWithRange:NSMakeRange((NSUInteger)i, 1)]];
        NSInteger rest = len - 1 - i;
        if (rest > 0 && rest % 3 == 0) [r appendString:@"."];
    }
    return r;
}

static NSString *igdemo_conComa(double v) {
    NSString *s = [NSString stringWithFormat:@"%.1f", v];
    return [s stringByReplacingOccurrencesOfString:@"." withString:@","];
}

static NSString *igdemo_formatCantidad(double nv) {
    if (nv >= 1000000) {
        double m = nv / 1000000.0;
        if (m >= 10) return [NSString stringWithFormat:@"%.0f M", m];
        return [NSString stringWithFormat:@"%@ M", igdemo_conComa(m)];
    }
    if (nv >= 100000) return [NSString stringWithFormat:@"%@ mil", igdemo_miles((NSInteger)(nv / 1000.0))];
    if (nv >= 10000)  return [NSString stringWithFormat:@"%@ mil", igdemo_conComa(nv / 1000.0)];
    return igdemo_miles((NSInteger)nv);
}

// R1: 12,881 | 1.234.567 | 12,881 mil | 1.234 M
static NSRegularExpression *igdemo_reMiles() {
    static NSRegularExpression *re;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d{1,3}(?:[.,]\\d{3})+)(\\s*(mil|m|k))?\\s*$"
                                                       options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return re;
}

// R2: 12,4 mil | 2,3 M | 12 mil
static NSRegularExpression *igdemo_reSufijo() {
    static NSRegularExpression *re;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d{1,3})(?:,([1-9]\\d{0,1}))?\\s*(mil|m|k)\\s*$"
                                                       options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return re;
}

// R3: 847 (3 cifras sueltas, solo en etiquetas)
static NSRegularExpression *igdemo_rePlain() {
    static NSRegularExpression *re;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d{3})\\s*$" options:0 error:nil];
    });
    return re;
}

static NSString *igdemo_inflarLabel(NSString *s) {
    if (s.length == 0 || s.length > 16) return nil;

    NSTextCheckingResult *m1 = [igdemo_reMiles() firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m1 && [m1 rangeAtIndex:1].location != NSNotFound) {
        NSString *num = [s substringWithRange:[m1 rangeAtIndex:1]];
        NSString *sep = nil;
        for (NSUInteger i = 0; i < num.length; i++) {
            unichar c = [num characterAtIndex:i];
            if (c == ',' || c == '.') sep = [NSString stringWithFormat:@"%c", c];
        }
        NSString *limpio = [[num stringByReplacingOccurrencesOfString:@"." withString:@""]
                            stringByReplacingOccurrencesOfString:@"," withString:@""];
        double v = limpio.doubleValue;
        if (v <= 0) return nil;
        if ([m1 rangeAtIndex:3].location != NSNotFound) {
            NSString *suf = [[s substringWithRange:[m1 rangeAtIndex:3]] lowercaseString];
            if ([suf isEqualToString:@"mil"] || [suf isEqualToString:@"k"]) v *= 1000.0;
            else if ([suf isEqualToString:@"m"]) v *= 1000000.0;
            return igdemo_formatCantidad(v * kIGDemoViewsFactor);
        }
        NSString *base = igdemo_miles((NSInteger)(v * kIGDemoViewsFactor));
        if ([sep isEqualToString:@","]) base = [base stringByReplacingOccurrencesOfString:@"." withString:@","];
        return base;
    }

    NSTextCheckingResult *m2 = [igdemo_reSufijo() firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m2 && [m2 rangeAtIndex:1].location != NSNotFound) {
        double v = [[s substringWithRange:[m2 rangeAtIndex:1]] doubleValue];
        if ([m2 rangeAtIndex:2].location != NSNotFound) {
            NSString *dec = [s substringWithRange:[m2 rangeAtIndex:2]];
            double d = dec.doubleValue;
            while (d >= 1) d /= 10.0;
            v += d;
        }
        if (v <= 0) return nil;
        NSString *suf = [[s substringWithRange:[m2 rangeAtIndex:3]] lowercaseString];
        if ([suf isEqualToString:@"mil"] || [suf isEqualToString:@"k"]) v *= 1000.0;
        else if ([suf isEqualToString:@"m"]) v *= 1000000.0;
        return igdemo_formatCantidad(v * kIGDemoViewsFactor);
    }

    NSTextCheckingResult *m3 = [igdemo_rePlain() firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m3 && [m3 rangeAtIndex:1].location != NSNotFound) {
        double v = [[s substringWithRange:[m3 rangeAtIndex:1]] doubleValue];
        if (v <= 0) return nil;
        return igdemo_miles((NSInteger)(v * kIGDemoViewsFactor));
    }
    return nil;
}

static NSInteger g_labelLogs = 0;

%hook UILabel
- (void)setText:(NSString *)text {
    @try {
        if (text.length > 0 && text.length <= 16 && g_labelLogs < 60) {
            NSString *nuevo = igdemo_inflarLabel(text);
            if (nuevo && ![nuevo isEqualToString:text]) {
                g_labelLogs++;
                igdemo_log(@"LABEL: '%@' -> '%@'", text, nuevo);
                %orig(nuevo);
                return;
            }
        }
    } @catch (NSException *e) {}
    %orig;
}
- (void)setAttributedText:(NSAttributedString *)text {
    @try {
        if (text && text.length > 0 && text.length <= 16 && g_labelLogs < 60) {
            NSString *s = text.string;
            if (s) {
                NSString *nuevo = igdemo_inflarLabel(s);
                if (nuevo && ![nuevo isEqualToString:s]) {
                    g_labelLogs++;
                    igdemo_log(@"LABEL-ATTR: '%@' -> '%@'", s, nuevo);
                    NSDictionary *attrs = [text attributesAtIndex:0 effectiveRange:NULL];
                    NSAttributedString *na = [[NSAttributedString alloc] initWithString:nuevo attributes:attrs ?: @{}];
                    %orig(na);
                    return;
                }
            }
        }
    } @catch (NSException *e) {}
    %orig;
}
%end

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
    igdemo_log(@"tweak v0.0.13 (rotacion Espana + views x5 en etiquetas) cargado en %@", [[NSBundle mainBundle] bundleIdentifier]);
}
