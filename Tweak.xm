#import <Foundation/Foundation.h>

// Demo para clase - v0.0.3
// La pantalla de audiencia de Instagram es un payload "Bloks". Objetivo:
// INTERCAMBIAR el porcentaje de España con el de México (misma suma total,
// nadie nota nada). Si el número no está en texto plano, vuelca el payload
// a los logs para depurar.

#define IGDEMO_TAG "[IGDEMO]"

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

static BOOL igdemo_stringMentionsMexico(NSString *s) {
    return [s containsString:@"México"] || [s containsString:@"Mexico"] || [s containsString:@"🇲🇽"];
}

// Primer token tipo porcentaje: "27,0%", "12,4 %", "13,14%", ...
static NSString *igdemo_firstPercentToken(NSString *s) {
    if (!s || s.length == 0 || s.length > 200000) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\d+(?:[.,]\\d+)?\\s*%" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return nil;
    return [s substringWithRange:[m range]];
}

// Reemplaza el primer porcentaje del texto por el token dado
static NSString *igdemo_replaceFirstPercent(NSString *s, NSString *token) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\d+(?:[.,]\\d+)?\\s*%" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m || !token) return nil;
    return [s stringByReplacingCharactersInRange:[m range] withString:token];
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

// Referencia a una cadena candidata encontrada en el árbol
@interface IGDemoRef : NSObject
@property (strong) id parent;   // contenedor mutable que la sostiene
@property (strong) id key;      // clave o índice
@property (strong) NSString *s; // texto original
@property (strong) id inner;    // si la cadena era JSON embebido: el objeto ya parseado
@end
@implementation IGDemoRef
@end

// Recolecta cadenas candidatas (España o México con porcentaje) y, al pasar
// por JSON embebido, entra dentro y sigue recolectando.
static void igdemo_collect(id obj, NSInteger depth, NSMutableArray<IGDemoRef *> *refs, NSMutableSet<NSString *> *seen) {
    if (!obj || depth > 20) return;

    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in [(NSDictionary *)obj allKeys]) {
            id v = obj[k];
            if (![v isKindOfClass:[NSString class]]) { igdemo_collect(v, depth + 1, refs, seen); continue; }
            NSString *s = v;
            BOOL candidata = (igdemo_stringMentionsSpain(s) || igdemo_stringMentionsMexico(s)) && igdemo_firstPercentToken(s);
            if (candidata) {
                NSString *huella = [NSString stringWithFormat:@"%p|%@", obj, k];
                if (![seen containsObject:huella]) {
                    [seen addObject:huella];
                    IGDemoRef *r = [IGDemoRef new];
                    r.parent = obj; r.key = k; r.s = s;
                    [refs addObject:r];
                }
                continue;
            }
            // ¿JSON embebido?
            NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length > 1 && ([t hasPrefix:@"{"] || [t hasPrefix:@"["]) &&
                (igdemo_stringMentionsSpain(s) || igdemo_stringMentionsMexico(s) ||
                 [s containsString:@"audience"] || [s containsString:@"demograph"])) {
                NSData *d = [t dataUsingEncoding:NSUTF8StringEncoding];
                id inner = d ? [NSJSONSerialization JSONObjectWithData:d
                                                               options:(NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves)
                                                                 error:nil] : nil;
                if (inner) {
                    NSUInteger before = refs.count;
                    igdemo_collect(inner, depth + 1, refs, seen);
                    if (refs.count > before) {
                        IGDemoRef *r = [IGDemoRef new];
                        r.parent = obj; r.key = k; r.s = s; r.inner = inner;
                        [refs addObject:r];
                    }
                }
            }
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)obj;
        for (NSUInteger i = 0; i < arr.count; i++) {
            id v = arr[i];
            if ([v isKindOfClass:[NSString class]]) {
                NSString *s = v;
                BOOL candidata = (igdemo_stringMentionsSpain(s) || igdemo_stringMentionsMexico(s)) && igdemo_firstPercentToken(s);
                if (candidata) {
                    NSString *huella = [NSString stringWithFormat:@"%p|%lu", obj, (unsigned long)i];
                    if (![seen containsObject:huella]) {
                        [seen addObject:huella];
                        IGDemoRef *r = [IGDemoRef new];
                        r.parent = (NSMutableArray *)arr; r.key = @(i); r.s = s;
                        [refs addObject:r];
                    }
                    continue;
                }
                NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (t.length > 1 && ([t hasPrefix:@"{"] || [t hasPrefix:@"["]) &&
                    (igdemo_stringMentionsSpain(s) || igdemo_stringMentionsMexico(s) ||
                     [s containsString:@"audience"] || [s containsString:@"demograph"])) {
                    NSData *d = [t dataUsingEncoding:NSUTF8StringEncoding];
                    id inner = d ? [NSJSONSerialization JSONObjectWithData:d
                                                                   options:(NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves)
                                                                     error:nil] : nil;
                    if (inner) {
                        NSUInteger before = refs.count;
                        igdemo_collect(inner, depth + 1, refs, seen);
                        if (refs.count > before) {
                            IGDemoRef *r = [IGDemoRef new];
                            r.parent = (NSMutableArray *)arr; r.key = @(i); r.s = s; r.inner = inner;
                            [refs addObject:r];
                        }
                    }
                }
            } else {
                igdemo_collect(v, depth + 1, refs, seen);
            }
        }
    }
}

// Intercambia los porcentajes España <-> México entre las referencias halladas
static void igdemo_doSwap(NSMutableArray<IGDemoRef *> *refs, NSMutableSet<id> *modifiedInners, NSMutableArray<NSString *> *findings) {
    IGDemoRef *refE = nil, *refM = nil;
    for (IGDemoRef *r in refs) {
        if (!refE && igdemo_stringMentionsSpain(r.s)) refE = r;
        else if (!refM && igdemo_stringMentionsMexico(r.s)) refM = r;
    }
    if (!refE || !refM) {
        [findings addObject:[NSString stringWithFormat:@"falta candidato: España=%d México=%d", refE != nil, refM != nil]];
        return;
    }
    NSString *pE = igdemo_firstPercentToken(refE.s);
    NSString *pM = igdemo_firstPercentToken(refM.s);
    if (!pE || !pM) return;

    NSString *newE = igdemo_replaceFirstPercent(refE.s, pM);
    NSString *newM = igdemo_replaceFirstPercent(refM.s, pE);
    if (!newE || !newM) return;

    igdemo_setInParent(refE.parent, refE.key, newE);
    igdemo_setInParent(refM.parent, refM.key, newM);
    if (refE.inner) [modifiedInners addObject:refE.inner];
    if (refM.inner) [modifiedInners addObject:refM.inner];
    [findings addObject:[NSString stringWithFormat:@"SWAP: España %@ <-> México %@", pM, pE]];
}

// Re-serializa los JSON embebidos que cambiamos
static void igdemo_flushInners(NSMutableArray<IGDemoRef *> *refs, NSMutableSet<id> *modifiedInners) {
    for (IGDemoRef *r in refs) {
        if (r.inner && [modifiedInners containsObject:r.inner]) {
            NSData *nd = [NSJSONSerialization dataWithJSONObject:r.inner options:0 error:nil];
            if (nd) {
                NSString *ns = [[NSString alloc] initWithData:nd encoding:NSUTF8StringEncoding];
                igdemo_setInParent(r.parent, r.key, ns);
            }
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

        // Vuelco completo de payloads de audiencia (depuración)
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (raw && ([raw containsString:@"organic.reel.audience"] || igdemo_stringMentionsSpain(raw) || igdemo_stringMentionsMexico(raw))) {
            igdemo_dumpString(@"AUD", raw);
        }

        NSError *tmpErr = nil;
        id parsed = %orig(data, (opts | NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves), &tmpErr);
        if (!parsed) return %orig;

        NSMutableArray<IGDemoRef *> *refs = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        igdemo_collect(parsed, 0, refs, seen);

        NSMutableArray<NSString *> *findings = [NSMutableArray array];
        NSMutableSet<id> *modifiedInners = [NSMutableSet set];
        if (refs.count > 0) {
            igdemo_doSwap(refs, modifiedInners, findings);
            igdemo_flushInners(refs, modifiedInners);
        }

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
    igdemo_log(@"tweak v0.0.3 (swap España<->México) cargado en %@", [[NSBundle mainBundle] bundleIdentifier]);
}
