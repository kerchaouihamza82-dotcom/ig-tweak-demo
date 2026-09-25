#import <Foundation/Foundation.h>

// Demo para clase: cuando Instagram recibe los datos de audiencia
// (edad / género / países), si encuentra a España le sube el porcentaje.
// TODO el resto de la app queda intacto.

#define IGDEMO_TAG "[IGDEMO]"
static const double kIGDemoTarget = 26.0; // % que verá España

static void igdemo_log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%s %@", IGDEMO_TAG, msg);
}

// Escaneo barato del JSON crudo (sin convertirlo entero a string)
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

// "10.2%" -> "26%" (conserva el resto del formato)
static NSString *igdemo_rewritePercentString(NSString *s) {
    if (!s || s.length == 0 || s.length > 12) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\d+(?:[.,]\\d+)?" options:0 error:nil];
    NSTextCheckingResult *r = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!r || [r range].location != 0) return nil;
    return [s stringByReplacingCharactersInRange:[r range]
                                      withString:[NSString stringWithFormat:@"%ld", (long)kIGDemoTarget]];
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

static void igdemo_walk(id obj, NSInteger depth, NSMutableArray<NSString *> *findings) {
    if (!obj || depth > 14) return;

    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = (NSMutableDictionary *)obj;

        // Caso 1: mapa directo { "ES": 10.2, "MX": 8.0, ... }
        if (igdemo_looksLikeCountryMap(dict)) {
            id es = dict[@"ES"];
            if ([es isKindOfClass:[NSNumber class]]) {
                double v = [es doubleValue];
                if (v > 0 && v < 100) {
                    [findings addObject:[NSString stringWithFormat:@"mapa ES=%@", es]];
                    @try { [dict setObject:@(kIGDemoTarget) forKey:@"ES"]; } @catch (NSException *e) {}
                }
            } else if ([es isKindOfClass:[NSString class]]) {
                NSString *newS = igdemo_rewritePercentString(es);
                if (newS) {
                    [findings addObject:[NSString stringWithFormat:@"mapa ES(str)=%@", es]];
                    @try { [dict setObject:newS forKey:@"ES"]; } @catch (NSException *e) {}
                }
            }
        }

        // Caso 2: lista tipo { "name": "Spain" | "ES" | "España", "value": 10.2 }
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
                            @try { [dict setObject:@(kIGDemoTarget) forKey:vk]; } @catch (NSException *e) {}
                        }
                        break;
                    } else if ([v isKindOfClass:[NSString class]]) {
                        NSString *ns = igdemo_rewritePercentString(v);
                        if (ns) {
                            [findings addObject:[NSString stringWithFormat:@"lista %@ %@(str)=%@", nm, vk, v]];
                            @try { [dict setObject:ns forKey:vk]; } @catch (NSException *e) {}
                        }
                        break;
                    }
                }
            }
        }

        for (id k in [dict allKeys]) {
            igdemo_walk(dict[k], depth + 1, findings);
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            igdemo_walk(item, depth + 1, findings);
        }
    }
}

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opts error:(NSError **)error {
    @try {
        if (!igdemo_dataLooksRelevant(data)) return %orig;

        NSError *tmpErr = nil;
        id parsed = %orig(data, (opts | NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves), &tmpErr);
        if (!parsed) return %orig;

        NSMutableArray<NSString *> *findings = [NSMutableArray array];
        igdemo_walk(parsed, 0, findings);

        if (findings.count > 0) {
            igdemo_log(@">>> MODIFICADO: %@", [findings componentsJoinedByString:@"; "]);
        } else {
            NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!s) s = @"<no es texto>";
            if (s.length > 2500) {
                s = [NSString stringWithFormat:@"%@ ...[truncado, total %lu bytes]", [s substringToIndex:2500], (unsigned long)data.length];
            }
            igdemo_log(@"JSON relevante (sin cambio): %@", s);
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
    igdemo_log(@"tweak cargado en %@", [[NSBundle mainBundle] bundleIdentifier]);
}
