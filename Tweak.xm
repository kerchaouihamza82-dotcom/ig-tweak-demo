#import <Foundation/Foundation.h>

// Demo para clase - v0.0.2
// La pantalla de audiencia de Instagram es un payload "Bloks" (interfaz
// pre-cocinada del servidor). Esta version busca cadenas de texto que
// mencionen España y reemplaza el porcentaje que llevan al lado.
// Ademas vuelca a los logs los payloads de audiencia para depurar.

#define IGDEMO_TAG "[IGDEMO]"
static const double kIGDemoTarget = 26.0;
static NSString * const kIGDemoTargetPct = @"26%";

static void igdemo_log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%s %@", IGDEMO_TAG, msg);
}

static BOOL igdemo_stringMentionsSpain(NSString *s) {
    return [s containsString:@"España"] || [s containsString:@"Spain"] || [s containsString:@"🇪🇸"];
}

// Vuelca un texto a los logs en trozos para poder reconstruirlo
static void igdemo_dumpString(NSString *tag, NSString *s) {
    if (!s) return;
    NSUInteger len = MIN(s.length, (NSUInteger)60000);
    NSUInteger chunk = 1800;
    NSUInteger total = (len + chunk - 1) / chunk;
    for (NSUInteger i = 0; i < len; i += chunk) {
        NSUInteger e = MIN(i + chunk, len);
        igdemo_log(@"DUMP[%@ %lu/%lu] %@", tag, (unsigned long)(i / chunk + 1), (unsigned long)total,
                   [s substringWithRange:NSMakeRange(i, e - i)]);
    }
}

static void igdemo_walk(id obj, id parent, id key, NSInteger depth, NSMutableArray<NSString *> *findings);

// "12,4%" -> "26%"; "12.4 %" -> "26%" ; etc.
static NSString *igdemo_replaceFirstPercent(NSString *s) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\d+(?:[.,]\\d+)?\\s*%" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return nil;
    return [s stringByReplacingCharactersInRange:[m range] withString:kIGDemoTargetPct];
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

static void igdemo_mutateString(id parent, id key, NSString *s, NSInteger depth, NSMutableArray<NSString *> *findings) {
    if (findings.count > 40) return;
    if (![s isKindOfClass:[NSString class]] || s.length == 0 || s.length > 200000) return;

    // Caso A: texto visible "🇪🇸 España 12,4%" -> cambiar el porcentaje en el propio texto
    if (igdemo_stringMentionsSpain(s)) {
        NSString *newS = igdemo_replaceFirstPercent(s);
        if (newS) {
            [findings addObject:[NSString stringWithFormat:@"texto España: '%@' -> '%@'", s, newS]];
            igdemo_setInParent(parent, key, newS);
            return;
        }
        [findings addObject:[NSString stringWithFormat:@"texto España sin porcentaje: '%@'", s]];
    }

    // Caso B: la cadena es JSON embebido (typico de Bloks) -> parsear, recorrer y re-serializar
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length > 1 && ([t hasPrefix:@"{"] || [t hasPrefix:@"["]) &&
        (igdemo_stringMentionsSpain(s) || [s containsString:@"audience"] || [s containsString:@"demograph"])) {
        NSData *d = [t dataUsingEncoding:NSUTF8StringEncoding];
        id inner = d ? [NSJSONSerialization JSONObjectWithData:d
                                                       options:(NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves)
                                                         error:nil] : nil;
        if (inner) {
            NSUInteger before = findings.count;
            igdemo_walk(inner, nil, nil, depth + 1, findings);
            if (findings.count > before) {
                NSData *nd = [NSJSONSerialization dataWithJSONObject:inner options:0 error:nil];
                if (nd) {
                    NSString *ns = [[NSString alloc] initWithData:nd encoding:NSUTF8StringEncoding];
                    igdemo_setInParent(parent, key, ns);
                }
            }
        }
    }
}

static BOOL igdemo_looksLikeCountryMap(NSDictionary *dict) {
    NSUInteger n = 0;
    for (NSString *k in dict) {
        if ([k isKindOfClass:[NSString class]] && k.length == 2 &&
            [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[k characterAtIndex:0]] &&
            [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[k characterAtIndex:1]]) {
            n++;
        }
    }
    return n >= 3;
}

static void igdemo_walk(id obj, id parent, id key, NSInteger depth, NSMutableArray<NSString *> *findings) {
    if (!obj || depth > 20) return;

    if ([obj isKindOfClass:[NSString class]]) {
        igdemo_mutateString(parent, key, obj, depth, findings);
        return;
    }

    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = (NSMutableDictionary *)obj;

        // Mapa directo { "ES": 12.4, "MX": 8.0, ... }
        if (igdemo_looksLikeCountryMap(dict)) {
            id es = dict[@"ES"];
            if ([es isKindOfClass:[NSNumber class]]) {
                double v = [es doubleValue];
                if (v > 0 && v < 100) {
                    [findings addObject:[NSString stringWithFormat:@"mapa ES=%@", es]];
                    igdemo_setInParent(dict, @"ES", @(kIGDemoTarget));
                }
            } else if ([es isKindOfClass:[NSString class]]) {
                NSString *newS = igdemo_replaceFirstPercent(es);
                if (newS) {
                    [findings addObject:[NSString stringWithFormat:@"mapa ES(str)=%@ -> %@", es, newS]];
                    igdemo_setInParent(dict, @"ES", newS);
                }
            }
        }

        // Lista tipo { "name": "Spain" | "ES" | "España", "value": 12.4 }
        id nm = dict[@"name"] ?: dict[@"label"] ?: dict[@"key"];
        if ([nm isKindOfClass:[NSString class]]) {
            NSString *l = [nm lowercaseString];
            BOOL isSpain = ([nm isEqualToString:@"ES"] || [l isEqualToString:@"spain"] ||
                            [l isEqualToString:@"españa"] || [l isEqualToString:@"espana"] || [l isEqualToString:@"es"]);
            if (isSpain) {
                for (NSString *vk in @[@"value", @"percentage", @"percent", @"count", @"share", @"ratio"]) {
                    id v = dict[vk];
                    if ([v isKindOfClass:[NSNumber class]]) {
                        double d = [v doubleValue];
                        if (d >= 0 && d <= 100) {
                            [findings addObject:[NSString stringWithFormat:@"lista %@ %@=%@", nm, vk, v]];
                            igdemo_setInParent(dict, vk, @(kIGDemoTarget));
                        }
                        break;
                    }
                }
            }
        }

        for (id k in [dict allKeys]) {
            igdemo_walk(dict[k], dict, k, depth + 1, findings);
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        for (NSUInteger i = 0; i < arr.count; i++) {
            igdemo_walk(arr[i], (NSMutableArray *)arr, @(i), depth + 1, findings);
        }
    }
}

// Escaneo barato del JSON crudo
static BOOL igdemo_dataLooksRelevant(NSData *data) {
    if (!data || data.length < 16) return NO;
    static NSArray<NSData *> *markers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        markers = @[ [@"country" dataUsingEncoding:NSUTF8StringEncoding],
                     [@"Country" dataUsingEncoding:NSUTF8StringEncoding],
                     [@"demograph" dataUsingEncoding:NSUTF8StringEncoding],
                     [@"audience" dataUsingEncoding:NSUTF8StringEncoding],
                     [@"\"geo\"" dataUsingEncoding:NSUTF8StringEncoding],
                     [@"geographic" dataUsingEncoding:NSUTF8StringEncoding] ];
    });
    NSRange whole = NSMakeRange(0, data.length);
    for (NSData *m in markers) {
        if ([data rangeOfData:m options:0 range:whole].location != NSNotFound) return YES;
    }
    return NO;
}

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opts error:(NSError **)error {
    @try {
        if (!igdemo_dataLooksRelevant(data)) return %orig;

        // Vuelco completo de los payloads de audiencia (para depurar la estructura)
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (raw && ([raw containsString:@"organic.reel.audience"] || igdemo_stringMentionsSpain(raw))) {
            igdemo_dumpString(@"AUD", raw);
        }

        NSError *tmpErr = nil;
        id parsed = %orig(data, (opts | NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves), &tmpErr);
        if (!parsed) return %orig;

        NSMutableArray<NSString *> *findings = [NSMutableArray array];
        igdemo_walk(parsed, nil, nil, 0, findings);

        if (findings.count > 0) {
            igdemo_log(@">>> %lu CAMBIOS: %@", (unsigned long)findings.count, [findings componentsJoinedByString:@"; "]);
        }
        return parsed;
    } @catch (NSException *e) {
        igdemo_log(@"excepcion: %@", e);
        return %orig;
    }
}
%end

%ctor {
    %init;
    igdemo_log(@"tweak v0.0.2 cargado en %@", [[NSBundle mainBundle] bundleIdentifier]);
}
