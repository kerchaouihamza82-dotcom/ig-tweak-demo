#import <Foundation/Foundation.h>

// Demo para clase - v0.0.4
// La pantalla de audiencia llega como payload "Bloks": cada país es una fila
// con nombre, porcentaje y barra como componentes separados.
// Estrategia: localizar los nodos "España" y "México", tomar los valores de
// porcentaje/barra de SU fila (por proximidad en el árbol) e intercambiar las
// dos filas entre sí (valores y nombres). La suma total no cambia.

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

static void igdemo_dumpString(NSString *tag, NSString *s) {
    if (!s) return;
    static NSMutableSet *vistos;
    static NSInteger restantes = 3;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ vistos = [NSMutableSet set]; });
    NSString *huella = [NSString stringWithFormat:@"%lu", (unsigned long)[[s substringToIndex:MIN(s.length, (NSUInteger)2000)] hash]];
    if ([vistos containsObject:huella] || restantes <= 0) return;
    [vistos addObject:huella];
    restantes--;
    NSUInteger len = MIN(s.length, (NSUInteger)30000);
    NSUInteger chunk = 500;
    NSUInteger total = (len + chunk - 1) / chunk;
    for (NSUInteger i = 0; i < len; i += chunk) {
        NSUInteger e = MIN(i + chunk, len);
        igdemo_log(@"DUMP[%@ %lu/%lu] %@", tag, (unsigned long)(i / chunk + 1), (unsigned long)total,
                   [s substringWithRange:NSMakeRange(i, e - i)]);
    }
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

// Fila de un nombre = nodos porcentaje cuyo LCA con el nombre es más profundo
// que el LCA con cualquier OTRO nombre de país.
static NSArray<IGDemoNode *> *igdemo_filaDe(IGDemoNode *nombre, NSArray<IGDemoNode *> *todosLosNombres, NSArray<IGDemoNode *> *pcts) {
    NSInteger limite = 0;
    for (IGDemoNode *otro in todosLosNombres) {
        if (otro == nombre) continue;
        NSInteger d = igdemo_lcaDepth(nombre.path, otro.path);
        if (d > limite) limite = d;
    }
    NSMutableArray<IGDemoNode *> *fila = [NSMutableArray array];
    for (IGDemoNode *p in pcts) {
        if (igdemo_lcaDepth(nombre.path, p.path) > limite) [fila addObject:p];
    }
    return fila;
}

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opts error:(NSError **)error {
    @try {
        if (!data || data.length < 16) return %orig;

        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        BOOL pareceAudience = raw && ([raw containsString:@"audience"] || [raw containsString:@"demograph"] ||
                                      igdemo_stringMentionsSpain(raw) || igdemo_stringMentionsMexico(raw));
        if (!pareceAudience) return %orig;

        if (raw) igdemo_dumpString(@"AUD", raw);

        NSError *tmpErr = nil;
        id parsed = %orig(data, (opts | NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves), &tmpErr);
        if (!parsed) return %orig;

        g_nodos = [NSMutableArray array];
        igdemo_scanNode(parsed, nil, nil, [NSMutableArray array]);

        NSMutableArray<IGDemoNode *> *namesE = [NSMutableArray array];
        NSMutableArray<IGDemoNode *> *namesM = [NSMutableArray array];
        NSMutableArray<IGDemoNode *> *pcts = [NSMutableArray array];
        for (IGDemoNode *n in g_nodos) {
            if (igdemo_isPurePct(n.s)) { [pcts addObject:n]; continue; }
            if (n.s.length < 40) {
                if (igdemo_stringMentionsSpain(n.s)) [namesE addObject:n];
                else if (igdemo_stringMentionsMexico(n.s)) [namesM addObject:n];
            }
        }

        if (namesE.count == 0 || namesM.count == 0 || pcts.count == 0) {
            igdemo_log(@"sin candidatos: E=%lu M=%lu pct=%lu",
                       (unsigned long)namesE.count, (unsigned long)namesM.count, (unsigned long)pcts.count);
            id r = parsed;
            g_nodos = nil;
            return r;
        }

        // Elegir el nombre de cada país cuya fila tenga más valores (la fila
        // real del listado, no menciones sueltas en otros textos)
        IGDemoNode *nameE = nil, *nameM = nil;
        NSArray<IGDemoNode *> *filaE = nil, *filaM = nil;
        for (IGDemoNode *candidato in namesE) {
            NSArray<IGDemoNode *> *f = igdemo_filaDe(candidato, [namesE arrayByAddingObjectsFromArray:namesM], pcts);
            if (!filaE || f.count > filaE.count) { filaE = f; nameE = candidato; }
        }
        for (IGDemoNode *candidato in namesM) {
            NSArray<IGDemoNode *> *f = igdemo_filaDe(candidato, [namesE arrayByAddingObjectsFromArray:namesM], pcts);
            if (!filaM || f.count > filaM.count) { filaM = f; nameM = candidato; }
        }

        igdemo_log(@"nodos: namesE=%lu namesM=%lu pcts=%lu filaE=%lu filaM=%lu",
                   (unsigned long)namesE.count, (unsigned long)namesM.count, (unsigned long)pcts.count,
                   (unsigned long)filaE.count, (unsigned long)filaM.count);

        NSMutableArray<NSString *> *findings = [NSMutableArray array];

        if (filaE.count > 0 && filaM.count > 0) {
            NSUInteger n = MIN(filaE.count, filaM.count);
            for (NSUInteger i = 0; i < n; i++) {
                NSString *vE = filaE[i].s;
                NSString *vM = filaM[i].s;
                if (![vE isEqualToString:vM]) {
                    igdemo_setInParent(filaE[i].parent, filaE[i].key, vM);
                    igdemo_setInParent(filaM[i].parent, filaM[i].key, vE);
                }
            }
            [findings addObject:[NSString stringWithFormat:@"filas intercambiadas (%lu valores)", (unsigned long)n]];

            NSString *nE_txt = nameE.s;
            NSString *nM_txt = nameM.s;
            igdemo_setInParent(nameE.parent, nameE.key, nM_txt);
            igdemo_setInParent(nameM.parent, nameM.key, nE_txt);
            [findings addObject:@"nombres intercambiados"];
        } else {
            [findings addObject:@"filas vacias, sin swap"];
        }

        for (NSString *f in findings) igdemo_log(@">>> %@", f);

        id r = parsed;
        g_nodos = nil;
        return r;
    } @catch (NSException *e) {
        igdemo_log(@"excepcion: %@", e);
        return %orig;
    }
}
%end

%ctor {
    %init;
    igdemo_log(@"tweak v0.0.4 (swap filas Espana<->Mexico) cargado en %@", [[NSBundle mainBundle] bundleIdentifier]);
}
